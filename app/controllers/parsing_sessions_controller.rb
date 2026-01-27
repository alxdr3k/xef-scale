class ParsingSessionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :require_workspace_access
  before_action :require_workspace_write_access, only: [ :create, :create_from_text ]

  def index
    @parsing_sessions = @workspace.parsing_sessions
                                  .includes(:processed_file)
                                  .order(created_at: :desc)

    @pagy, @parsing_sessions = pagy(@parsing_sessions, items: 20)
  end

  def show
    @parsing_session = @workspace.parsing_sessions.find(params[:id])

    # Redirect to review page if session is completed
    if @parsing_session.completed?
      redirect_to review_workspace_parsing_session_path(@workspace, @parsing_session)
      return
    end

    @duplicate_confirmations = @parsing_session.duplicate_confirmations
                                               .includes(:original_transaction, :new_transaction)
                                               .order(:created_at)
  end

  def create
    unless params[:file].present?
      redirect_to workspace_parsing_sessions_path(@workspace), alert: "파일을 선택해 주세요."
      return
    end

    uploaded_file = params[:file]

    @processed_file = @workspace.processed_files.build(
      filename: uploaded_file.original_filename,
      original_filename: uploaded_file.original_filename,
      status: "pending",
      uploaded_by: current_user
    )
    @processed_file.file.attach(uploaded_file)

    if @processed_file.save
      # Queue background job for parsing
      FileParsingJob.perform_later(@processed_file.id)
      redirect_to workspace_parsing_sessions_path(@workspace),
                  notice: "파일이 업로드되었습니다. 처리 중입니다..."
    else
      redirect_to workspace_parsing_sessions_path(@workspace),
                  alert: "파일 업로드에 실패했습니다."
    end
  end

  def create_from_text
    unless params[:raw_text].present?
      redirect_to workspace_parsing_sessions_path(@workspace), alert: "텍스트를 입력해 주세요."
      return
    end

    unless params[:financial_institution] == "shinhan_card"
      redirect_to workspace_parsing_sessions_path(@workspace), alert: "지원되지 않는 금융기관입니다."
      return
    end

    # Validate financial institution exists
    institution = FinancialInstitution.find_by(identifier: "shinhan_card")
    unless institution
      redirect_to workspace_parsing_sessions_path(@workspace),
                  alert: "금융기관 정보가 설정되지 않았습니다. 관리자에게 문의하세요."
      return
    end

    begin
      # Parse text immediately (no background job needed)
      Rails.logger.info "[TextParser] Raw text (first 500 chars): #{params[:raw_text].to_s[0..500].inspect}"
      Rails.logger.info "[TextParser] Raw text lines: #{params[:raw_text].to_s.split("\n").first(10).map(&:inspect)}"

      parser = Parsers::ShinhanTextParser.new(params[:raw_text], workspace: @workspace)
      transactions_data = parser.parse

      Rails.logger.info "[TextParser] Parsed #{transactions_data.size} transactions"

      if transactions_data.empty?
        redirect_to workspace_parsing_sessions_path(@workspace),
                    alert: "텍스트에서 거래 내역을 찾을 수 없습니다. 형식을 확인해 주세요."
        return
      end

      parsing_session = nil
      stats = { total: transactions_data.size, success: 0, duplicate: 0, error: 0 }

      # Wrap everything in a transaction for atomicity
      ActiveRecord::Base.transaction do
        # Create parsing session (without processed_file)
        parsing_session = @workspace.parsing_sessions.create!(
          source_type: "text_paste",
          status: "processing",
          review_status: "pending_review"
        )
        parsing_session.start!

        # Create transactions
        uncategorized_transactions = []

        transactions_data.each do |tx_data|
          begin
            transaction = create_transaction_from_data(@workspace, tx_data, parsing_session, institution)
            uncategorized_transactions << transaction if transaction.category_id.nil?

            # Check for duplicates
            duplicate = find_duplicate_transaction(@workspace, transaction)
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

        # Categorize uncategorized transactions with Gemini (outside transaction is OK, it's best-effort)
        if uncategorized_transactions.any?
          categorize_with_gemini(uncategorized_transactions)
        end

        parsing_session.complete!(stats)
      end

      redirect_to review_workspace_parsing_session_path(@workspace, parsing_session),
                  notice: "#{stats[:success]}건의 거래가 파싱되었습니다."
    rescue StandardError => e
      Rails.logger.error "Text parsing failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      redirect_to workspace_parsing_sessions_path(@workspace),
                  alert: "텍스트 파싱 중 오류가 발생했습니다: #{e.message}"
    end
  end

  private

  def create_transaction_from_data(workspace, tx_data, parsing_session, institution = nil)
    category = match_category_for_merchant(workspace, tx_data[:merchant])
    institution ||= FinancialInstitution.find_by(identifier: tx_data[:institution_identifier])

    workspace.transactions.create!(
      date: tx_data[:date],
      merchant: tx_data[:merchant],
      description: tx_data[:description],
      amount: tx_data[:amount],
      installment_month: tx_data[:installment_month],
      installment_total: tx_data[:installment_total],
      payment_type: tx_data[:payment_type] || "lump_sum",
      category: category,
      financial_institution: institution,
      status: "pending_review",
      parsing_session: parsing_session
    )
  end

  def match_category_for_merchant(workspace, merchant)
    return nil if merchant.blank?

    # First try CategoryMapping
    mapping = CategoryMapping.find_for_merchant(workspace, merchant)
    return mapping.category if mapping

    # Then try Category keyword matching
    workspace.categories.find { |c| c.matches?(merchant) }
  end

  def find_duplicate_transaction(workspace, transaction)
    workspace.transactions
             .reviewable
             .where(
               date: transaction.date,
               merchant: transaction.merchant,
               amount: transaction.amount
             )
             .where.not(id: transaction.id)
             .first
  end

  def categorize_with_gemini(transactions)
    return if transactions.blank?

    merchants = transactions.map(&:merchant).compact.uniq
    return if merchants.blank?

    gemini_service = GeminiCategoryService.new
    results = gemini_service.suggest_categories_batch(merchants, @workspace.categories.to_a)
    return if results.blank?

    transactions.each do |transaction|
      category_name = results[transaction.merchant]
      next unless category_name

      category = @workspace.categories.find_by(name: category_name)
      next unless category

      transaction.update!(category: category)

      # Use find_or_create_by to avoid race condition
      CategoryMapping.find_or_create_by!(
        workspace: @workspace,
        merchant_pattern: transaction.merchant,
        description_pattern: nil
      ) do |mapping|
        mapping.category = category
        mapping.source = "gemini"
      end
    end
  rescue ArgumentError => e
    Rails.logger.warn "Gemini API disabled: #{e.message}"
  rescue ActiveRecord::RecordNotUnique
    # Another thread created the mapping, which is fine
  rescue StandardError => e
    Rails.logger.error "Gemini API error: #{e.message}"
  end
end
