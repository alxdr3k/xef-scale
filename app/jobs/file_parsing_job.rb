class FileParsingJob < ApplicationJob
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(processed_file_id, institution_identifier: nil)
    processed_file = ProcessedFile.find(processed_file_id)
    @institution_identifier = institution_identifier

    parsing_session = nil
    ProcessedFile.transaction do
      processed_file.lock!

      existing = processed_file.parsing_session
      if existing&.completed? || existing&.review_committed? || existing&.processing?
        return
      end

      parsing_session = existing || processed_file.create_parsing_session!(
        workspace_id: processed_file.workspace_id,
        status: "processing",
        review_status: "pending_review"
      )
      processed_file.mark_processing! unless processed_file.processing?
      parsing_session.start! unless parsing_session.processing?
    end

    begin
      result = parse_file(processed_file)

      user = processed_file.uploaded_by

      excluded = user&.excluded_merchants || []
      if excluded.any?
        result = result.reject { |tx| excluded.any? { |pattern| tx[:merchant]&.include?(pattern) } }
      end

      workspace = processed_file.workspace

      stats = { total: result.size, success: 0, duplicate: 0, error: 0, gemini: 0 }
      uncategorized_transactions = []

      result.each do |tx_data|
        begin
          transaction = create_transaction_without_gemini(workspace, tx_data, parsing_session)

          uncategorized_transactions << transaction if transaction.category_id.nil?

          match = DuplicateDetector.new(workspace, transaction).find_match
          if match
            parsing_session.duplicate_confirmations.create!(
              original_transaction: match.transaction,
              new_transaction: transaction,
              status: "pending",
              match_confidence: match.confidence,
              match_score: match.score
            )
            stats[:duplicate] += 1
          end

          stats[:success] += 1
        rescue StandardError => e
          Rails.logger.error "Failed to create transaction: #{e.message}"
          stats[:error] += 1
        end
      end

      if uncategorized_transactions.any? && workspace.ai_category_suggestions_enabled?
        gemini_count = categorize_with_gemini_batch(workspace, uncategorized_transactions)
        stats[:gemini] = gemini_count
      end

      if stats[:total].zero? || stats[:success].zero?
        parsing_session.fail!
        processed_file.mark_failed!
        create_failure_notifications(parsing_session)
      else
        parsing_session.complete!(stats)
        processed_file.mark_completed!
        create_completion_notifications(parsing_session)
      end

    rescue => e
      Rails.logger.error "Parsing failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      parsing_session.fail!
      processed_file.mark_failed!
      create_failure_notifications(parsing_session) if parsing_session
    ensure
      begin
        parsing_session.fail! if parsing_session&.processing?
      rescue ActiveRecord::ActiveRecordError => e
        Rails.logger.warn "[FileParsingJob] Could not mark session as failed: #{e.class} #{e.message}"
      end
      begin
        processed_file.mark_failed! if processed_file&.reload&.processing?
      rescue ActiveRecord::ActiveRecordError => e
        Rails.logger.warn "[FileParsingJob] Could not mark file as failed: #{e.class} #{e.message}"
      end
    end
  end

  private

  def parse_file(processed_file)
    ImageStatementParser.new(processed_file, institution_identifier: @institution_identifier).parse
  end

  def create_transaction_without_gemini(workspace, tx_data, parsing_session)
    match = match_category_without_gemini(workspace, tx_data[:merchant], amount: tx_data[:amount])

    # institution_identifier is an import hint from the processed_file; store it
    # in source_metadata rather than linking a FinancialInstitution record.
    metadata = build_source_metadata(tx_data)

    workspace.transactions.create!(
      date: tx_data[:date],
      merchant: tx_data[:merchant],
      description: tx_data[:description],
      amount: tx_data[:amount],
      installment_month: tx_data[:installment_month],
      installment_total: tx_data[:installment_total],
      payment_type: tx_data[:payment_type] || "lump_sum",
      original_amount: tx_data[:original_amount],
      benefit_type: tx_data[:benefit_type],
      benefit_amount: tx_data[:benefit_amount],
      category: match[:category],
      classification_source: match[:source],
      status: "pending_review",
      parsing_session: parsing_session,
      source_type: "image_upload",
      parse_confidence: tx_data[:confidence],
      source_metadata: metadata
    )
  end

  def build_source_metadata(tx_data)
    meta = { "source_channel" => "screenshot" }
    raw_institution = tx_data[:source_institution_raw].to_s.strip.presence
    meta["source_institution_raw"] = raw_institution if raw_institution
    meta["parser_confidence"] = tx_data[:confidence].to_f if tx_data[:confidence].present?
    meta
  end

  # ADR-0011 §Decision 3: 이미지 경로 1·2단계(mapping/keyword) 폴백에서 어느 단계가
  # 카테고리를 결정했는지 함께 반환. 3단계(gemini_batch)는
  # `categorize_with_gemini_batch`에서 별도 처리.
  # 반환: { category: Category|nil, source: "mapping_match"|"keyword_match"|nil }
  def match_category_without_gemini(workspace, merchant, amount: nil)
    return { category: nil, source: nil } if merchant.blank?

    mapping = CategoryMapping.find_for_merchant(workspace, merchant, amount: amount)
    return { category: mapping.category, source: "mapping_match" } if mapping

    keyword_category = workspace.categories.find { |c| c.matches?(merchant) }
    return { category: keyword_category, source: "keyword_match" } if keyword_category

    { category: nil, source: nil }
  end

  def categorize_with_gemini_batch(workspace, transactions)
    return 0 if transactions.blank?

    merchants = transactions.map(&:merchant).compact.uniq
    return 0 if merchants.blank?

    Rails.logger.info "[FileParsingJob] Gemini 배치 처리 시작: #{merchants.size}개 merchant"

    gemini_service = GeminiCategoryService.new
    results = gemini_service.suggest_categories_batch(merchants, workspace.categories.to_a)

    return 0 if results.blank?

    categorized_count = 0

    transactions.each do |transaction|
      category_name = results[transaction.merchant]
      next unless category_name

      category = workspace.categories.find_by(name: category_name)
      next unless category

      # ADR-0011 §Decision 3: 3단계 Gemini 배치 결과는 `gemini_batch`로 기록.
      transaction.update!(category: category, classification_source: "gemini_batch")
      categorized_count += 1

      begin
        CategoryMapping.find_or_create_by!(
          workspace: workspace,
          merchant_pattern: transaction.merchant,
          description_pattern: nil,
          match_type: "exact",
          amount: nil
        ) do |mapping|
          mapping.category = category
          mapping.source = "gemini"
        end
      rescue ActiveRecord::RecordNotUnique
      end
    end

    Rails.logger.info "[FileParsingJob] Gemini 배치 처리 완료: #{categorized_count}건 분류됨"
    categorized_count
  rescue ArgumentError => e
    Rails.logger.warn "[FileParsingJob] Gemini API 비활성화: #{e.message}"
    0
  rescue StandardError => e
    Rails.logger.error "[FileParsingJob] Gemini API 오류: #{e.message}"
    0
  end

  def create_failure_notifications(parsing_session)
    workspace = parsing_session.workspace

    if workspace.owner
      Notification.create_parsing_failed!(parsing_session, workspace.owner)
    end

    workspace.workspace_memberships.where(role: %w[co_owner member_write]).find_each do |membership|
      next if membership.user_id == workspace.owner_id

      Notification.create_parsing_failed!(parsing_session, membership.user)
    end
  end

  def create_completion_notifications(parsing_session)
    workspace = parsing_session.workspace

    if workspace.owner
      Notification.create_parsing_complete!(parsing_session, workspace.owner)
    end

    workspace.workspace_memberships.where(role: %w[co_owner member_write member_read]).find_each do |membership|
      next if membership.user_id == workspace.owner_id

      Notification.create_parsing_complete!(parsing_session, membership.user)
    end
  end
end
