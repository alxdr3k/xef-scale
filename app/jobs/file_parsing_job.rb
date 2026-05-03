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
      result, incomplete_result = extract_parse_result(parse_file(processed_file))

      user = processed_file.uploaded_by

      excluded = (user&.excluded_merchants || []).reject(&:blank?)
      if excluded.any?
        result = result.reject { |tx| excluded.any? { |pattern| tx[:merchant]&.include?(pattern) } }
        incomplete_result = incomplete_result.reject { |tx| excluded.any? { |pattern| tx[:merchant]&.include?(pattern) } }
      end

      workspace = processed_file.workspace

      stats = { total: result.size + incomplete_result.size, success: 0, duplicate: 0, error: incomplete_result.size, gemini: 0 }
      uncategorized_transactions = []
      record_import_issues(parsing_session, processed_file, incomplete_result) if incomplete_result.any?
      duplicate_policy = ImportDuplicatePolicy.new(
        workspace: workspace,
        parsing_session: parsing_session,
        source_type: "image_upload",
        processed_file: processed_file
      )

      result.each do |tx_data|
        begin
          transaction = create_transaction_without_gemini(workspace, tx_data, parsing_session)

          duplicate_result = duplicate_policy.apply(transaction, raw_payload: tx_data)
          unless duplicate_result.no_duplicate?
            stats[:duplicate] += 1
            next
          end

          uncategorized_transactions << transaction if transaction.category_id.nil?
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

      has_import_exceptions = stats[:error].positive? || parsing_session.open_import_issues.exists?

      if parsing_failed_without_import_outcome?(stats, parsing_session)
        parsing_session.update!(
          total_count: stats[:total],
          success_count: stats[:success],
          duplicate_count: stats[:duplicate],
          error_count: stats[:error]
        )
        parsing_session.fail!
        processed_file.mark_failed!
        create_failure_notifications(parsing_session)
        create_import_repair_notifications_safely(parsing_session)
      else
        committed_transactions = parsing_session.auto_commit_ready_transactions!(
          user: user,
          has_import_exceptions: has_import_exceptions
        )
        parsing_session.complete!(stats)
        processed_file.mark_completed!
        create_success_side_effects(parsing_session, workspace, committed_transactions)
      end

    rescue => e
      Rails.logger.error "[FileParsingJob] Parsing failed: #{e.class} #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      parsing_session&.fail!
      processed_file&.mark_failed!
      if parsing_session
        create_failure_notifications(parsing_session)
        create_import_repair_notifications_safely(parsing_session)
      end
    ensure
      if parsing_session&.processing?
        parsing_session.fail! rescue nil
      end
      if processed_file&.reload&.processing?
        processed_file.mark_failed! rescue nil
      end
    end
  end

  private

  def parse_file(processed_file)
    parser = ImageStatementParser.new(processed_file, institution_identifier: @institution_identifier)
    transactions = parser.parse
    { transactions: transactions, incomplete_transactions: parser.incomplete_transactions }
  end

  def extract_parse_result(parsed)
    if parsed.is_a?(Hash)
      [
        Array(parsed[:transactions] || parsed["transactions"]),
        Array(parsed[:incomplete_transactions] || parsed["incomplete_transactions"])
      ]
    else
      [ Array(parsed), [] ]
    end
  end

  def create_transaction_without_gemini(workspace, tx_data, parsing_session)
    category = match_category_without_gemini(workspace, tx_data[:merchant], amount: tx_data[:amount])

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
      category: category,
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

  def record_import_issues(parsing_session, processed_file, incomplete_transactions)
    incomplete_transactions.each do |tx|
      parsing_session.import_issues.create!(
        workspace: parsing_session.workspace,
        processed_file: processed_file,
        source_type: "image_upload",
        date: tx[:date] || tx["date"],
        merchant: tx[:merchant].presence || tx["merchant"].presence,
        amount: tx[:amount] || tx["amount"],
        missing_fields: import_issue_missing_fields(tx),
        raw_payload: import_issue_payload(tx)
      )
    end
  end

  def import_issue_missing_fields(tx)
    explicit = Array(tx[:missing_fields] || tx["missing_fields"]).map(&:to_s)
    filtered = explicit & ImportIssue::REQUIRED_FIELDS
    return filtered if filtered.any?

    ImportIssue::REQUIRED_FIELDS.select do |field|
      value = tx[field.to_sym] || tx[field]
      value.blank? || (field == "amount" && value.to_i == 0)
    end
  end

  def import_issue_payload(tx)
    tx.to_h.transform_keys(&:to_s).transform_values do |value|
      value.respond_to?(:iso8601) ? value.iso8601 : value
    end
  end

  def parsing_failed_without_import_outcome?(stats, parsing_session)
    return true if stats[:total].zero?
    return true if stats[:success].zero? && stats[:error].positive? && !parsing_session.open_import_issues.exists?

    stats[:success].zero? &&
      stats[:duplicate].zero? &&
      !parsing_session.open_import_issues.exists?
  end

  def match_category_without_gemini(workspace, merchant, amount: nil)
    return nil if merchant.blank?

    mapping = CategoryMapping.find_for_merchant(workspace, merchant, amount: amount)
    return mapping.category if mapping

    workspace.categories.find { |c| c.matches?(merchant) }
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

      transaction.update!(category: category)
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

  def create_success_side_effects(parsing_session, workspace, committed_transactions)
    create_budget_alerts(workspace, committed_transactions)
    create_completion_notifications_safely(parsing_session)
    create_import_repair_notifications_safely(parsing_session)
  end

  def create_budget_alerts(workspace, committed_transactions)
    BudgetAlertService.create_for_transactions!(workspace, committed_transactions)
  rescue StandardError => e
    Rails.logger.error "[FileParsingJob] Budget alert side effect failed: #{e.class} #{e.message}"
  end

  def create_completion_notifications_safely(parsing_session)
    create_completion_notifications(parsing_session)
  rescue StandardError => e
    Rails.logger.error "[FileParsingJob] Completion notification side effect failed: #{e.class} #{e.message}"
  end

  def create_import_repair_notifications_safely(parsing_session)
    create_import_repair_notifications(parsing_session)
  rescue StandardError => e
    Rails.logger.error "[FileParsingJob] Import repair notification side effect failed: #{e.class} #{e.message}"
  end

  def create_import_repair_notifications(parsing_session)
    ImportRepairNotifier.call(parsing_session)
  end

  def create_failure_notifications(parsing_session)
    workspace = parsing_session.workspace
    workspace.notification_recipients(roles: %w[co_owner member_write]).each do |user|
      Notification.create_parsing_failed!(parsing_session, user)
    rescue StandardError => e
      Rails.logger.error "[FileParsingJob] Failed to notify user #{user.id}: #{e.class} #{e.message}"
    end
  end

  def create_completion_notifications(parsing_session)
    workspace = parsing_session.workspace
    workspace.notification_recipients(roles: %w[co_owner member_write member_read]).each do |user|
      Notification.create_parsing_complete!(parsing_session, user)
    rescue StandardError => e
      Rails.logger.error "[FileParsingJob] Failed to notify user #{user.id}: #{e.class} #{e.message}"
    end
  end
end
