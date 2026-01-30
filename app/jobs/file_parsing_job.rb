require "open3"

class FileParsingJob < ApplicationJob
  queue_as :default

  IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .webp .heic].freeze

  def perform(processed_file_id, institution_identifier: nil)
    processed_file = ProcessedFile.find(processed_file_id)
    @institution_identifier = institution_identifier
    processed_file.mark_processing!

    parsing_session = processed_file.create_parsing_session!(
      workspace_id: processed_file.workspace_id,
      status: "processing",
      review_status: "pending_review"
    )
    parsing_session.start!

    begin
      result = parse_file(processed_file)
      workspace = processed_file.workspace

      # Create transactions (1차: CategoryMapping + keyword 매칭만 사용)
      stats = { total: result.size, success: 0, duplicate: 0, error: 0, gemini: 0 }
      uncategorized_transactions = []

      result.each do |tx_data|
        begin
          transaction = create_transaction_without_gemini(workspace, tx_data, parsing_session)

          # 카테고리가 없으면 나중에 Gemini로 처리
          uncategorized_transactions << transaction if transaction.category_id.nil?

          # Check for duplicates (only against committed transactions)
          duplicate = find_duplicate(workspace, transaction)
          if duplicate
            parsing_session.duplicate_confirmations.create!(
              original_transaction: duplicate,
              new_transaction: transaction,
              status: "pending"
            )
            stats[:duplicate] += 1
          end

          stats[:success] += 1
        rescue StandardError => e
          Rails.logger.error "Failed to create transaction: #{e.message}"
          stats[:error] += 1
        end
      end

      # 2차: 미분류 거래들을 Gemini로 일괄 처리
      if uncategorized_transactions.any?
        gemini_count = categorize_with_gemini_batch(workspace, uncategorized_transactions)
        stats[:gemini] = gemini_count
      end

      parsing_session.complete!(stats)
      processed_file.mark_completed!

      # Create notifications for workspace members
      create_completion_notifications(parsing_session)

    rescue => e
      Rails.logger.error "Parsing failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      parsing_session.fail!
      processed_file.mark_failed!
    ensure
      # Ensure status transitions even for non-StandardError exceptions (LoadError, SyntaxError, etc.)
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
    filename = processed_file.filename.downcase
    ext = File.extname(filename)

    if image_file?(ext) && @institution_identifier.present?
      parser = ParserRouter.route_by_identifier(@institution_identifier, processed_file)
      parser.parse
    elsif filename.end_with?(".xls", ".xlsx")
      # Use Python parser for Excel files (more reliable)
      parse_with_python(processed_file)
    else
      # Use Ruby parser for other formats (PDF, CSV)
      parser = ParserRouter.route(processed_file)
      parser.parse
    end
  end

  def image_file?(ext)
    IMAGE_EXTENSIONS.include?(ext)
  end

  def parse_with_python(processed_file)
    # Download file to temp location
    tempfile = download_to_tempfile(processed_file)

    begin
      result = PythonExcelParser.parse(tempfile.path)
      result[:transactions]
    ensure
      tempfile.close
      tempfile.unlink
    end
  end

  def download_to_tempfile(processed_file)
    blob_filename = processed_file.file.blob.filename.to_s
    extension = File.extname(blob_filename)
    basename = File.basename(blob_filename, extension)
    basename = "statement" if basename.blank?

    tempfile = Tempfile.new([ basename, extension ])
    tempfile.binmode
    tempfile.write(processed_file.file.download)
    tempfile.rewind
    tempfile
  end

  def create_transaction_without_gemini(workspace, tx_data, parsing_session)
    category = match_category_without_gemini(workspace, tx_data[:merchant])
    institution = FinancialInstitution.find_by(identifier: tx_data[:institution_identifier])

    workspace.transactions.create!(
      date: tx_data[:date],
      merchant: tx_data[:merchant],
      description: tx_data[:description],
      amount: tx_data[:amount],
      # 할부/혜택 관련 필드
      installment_month: tx_data[:installment_month],
      installment_total: tx_data[:installment_total],
      payment_type: tx_data[:payment_type] || "lump_sum",
      original_amount: tx_data[:original_amount],
      benefit_type: tx_data[:benefit_type],
      benefit_amount: tx_data[:benefit_amount],
      # 기존 필드
      category: category,
      financial_institution: institution,
      status: "pending_review",
      parsing_session: parsing_session
    )
  end

  def match_category_without_gemini(workspace, merchant)
    return nil if merchant.blank?

    # 1순위: CategoryMapping 테이블에서 찾기
    mapping = CategoryMapping.find_for_merchant(workspace, merchant)
    return mapping.category if mapping

    # 2순위: Category keyword 매칭
    workspace.categories.find { |c| c.matches?(merchant) }
  end

  def categorize_with_gemini_batch(workspace, transactions)
    return 0 if transactions.blank?

    # 중복 제거된 merchant 목록
    merchants = transactions.map(&:merchant).compact.uniq
    return 0 if merchants.blank?

    Rails.logger.info "[FileParsingJob] Gemini 배치 처리 시작: #{merchants.size}개 merchant"

    gemini_service = GeminiCategoryService.new
    results = gemini_service.suggest_categories_batch(merchants, workspace.categories.to_a)

    return 0 if results.blank?

    categorized_count = 0

    # 결과를 transaction에 적용하고 매핑 저장
    transactions.each do |transaction|
      category_name = results[transaction.merchant]
      next unless category_name

      category = workspace.categories.find_by(name: category_name)
      next unless category

      # 거래 업데이트
      transaction.update!(category: category)
      categorized_count += 1

      # 매핑 저장 - find_or_create_by로 Race Condition 방지
      begin
        CategoryMapping.find_or_create_by!(
          workspace: workspace,
          merchant_pattern: transaction.merchant,
          description_pattern: nil
        ) do |mapping|
          mapping.category = category
          mapping.source = "gemini"
        end
      rescue ActiveRecord::RecordNotUnique
        # Another thread created the mapping, which is fine
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

  def find_duplicate(workspace, transaction)
    scope = workspace.transactions
                     .reviewable
                     .where(date: transaction.date, amount: transaction.amount)
                     .where.not(id: transaction.id)

    # 할부 거래인 경우: installment_month도 비교
    if transaction.installment_month.present?
      scope = scope.where(installment_month: transaction.installment_month)
    else
      scope = scope.where(installment_month: nil)
    end

    scope.first
  end

  def create_completion_notifications(parsing_session)
    workspace = parsing_session.workspace

    # Notify workspace owner
    if workspace.owner
      Notification.create_parsing_complete!(parsing_session, workspace.owner)
    end

    # Notify workspace members with write access
    workspace.workspace_memberships.where(role: %w[co_owner member_write]).find_each do |membership|
      next if membership.user_id == workspace.owner_id

      Notification.create_parsing_complete!(parsing_session, membership.user)
    end
  end
end
