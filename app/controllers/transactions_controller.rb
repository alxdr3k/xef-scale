class TransactionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :require_workspace_access
  before_action :set_transaction, only: [ :show, :edit, :update, :destroy, :toggle_allowance, :quick_update_category, :inline_update ]
  before_action :require_workspace_write_access, only: [ :new, :create, :edit, :update, :destroy, :quick_update_category, :inline_update ]

  def index
    @year = params[:year].presence&.to_i || Date.current.year
    @month = params[:month].presence&.to_i

    transactions = @workspace.transactions.active.excluding_allowance.includes(:category, :financial_institution)

    # Filters
    transactions = transactions.for_year(@year) if @year && @month.nil?
    transactions = transactions.for_month(@year, @month) if @year && @month.present?
    transactions = transactions.by_category(params[:category_id]) if params[:category_id].present?
    transactions = transactions.by_institution(params[:institution_id]) if params[:institution_id].present?
    transactions = transactions.search(params[:q]) if params[:q].present?

    transactions = transactions.order(date: :desc, created_at: :desc)

    @pagy, @transactions = pagy(transactions, items: 50)

    # Stats
    @total_amount = transactions.sum(:amount)
    @categories = @workspace.categories.order(:name)
    @institutions = FinancialInstitution.order(:name)

    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  def show
  end

  def new
    @transaction = @workspace.transactions.build(date: Date.current)
    @categories = @workspace.categories
    @institutions = FinancialInstitution.all
  end

  def create
    @transaction = @workspace.transactions.build(transaction_params)

    if @transaction.save
      @categories = @workspace.categories.order(:name)
      respond_to do |format|
        format.html { redirect_to workspace_transactions_path(@workspace), notice: "거래가 추가되었습니다." }
        format.turbo_stream { flash[:notice] = "거래가 추가되었습니다." }
      end
    else
      @categories = @workspace.categories
      @institutions = FinancialInstitution.all
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @categories = @workspace.categories
    @institutions = FinancialInstitution.all
  end

  def update
    old_category_id = @transaction.category_id
    old_allowance_status = @transaction.allowance?

    if @transaction.update(transaction_params)
      # 카테고리가 변경되었으면 매핑 생성
      if transaction_params[:category_id].present? && transaction_params[:category_id].to_i != old_category_id
        create_category_mapping(@transaction, @transaction.category)
      end

      # Handle allowance toggle if present in params
      if params[:allowance].present?
        new_allowance_status = params[:allowance] == "1"
        if new_allowance_status != old_allowance_status
          if new_allowance_status
            AllowanceTransaction.mark_as_allowance!(@transaction, current_user)
          else
            AllowanceTransaction.unmark_as_allowance!(@transaction, current_user)
          end
          # Reload to get updated allowance status
          @transaction = @workspace.transactions
                                   .includes(:allowance_transaction, :category, :financial_institution)
                                   .find(@transaction.id)
        end
      end

      @categories = @workspace.categories.order(:name)
      respond_to do |format|
        format.html { redirect_to params[:return_to].presence || workspace_transactions_path(@workspace), notice: "거래가 수정되었습니다." }
        format.turbo_stream { flash[:notice] = "거래가 수정되었습니다." }
      end
    else
      @categories = @workspace.categories
      @institutions = FinancialInstitution.all
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @transaction.soft_delete!

    respond_to do |format|
      format.html { redirect_to workspace_transactions_path(@workspace), notice: "거래가 삭제되었습니다." }
      format.turbo_stream { flash.now[:notice] = "거래가 삭제되었습니다." }
    end
  end

  def toggle_allowance
    if @transaction.allowance?
      AllowanceTransaction.unmark_as_allowance!(@transaction, current_user)
      notice = "용돈에서 제외되었습니다."
    else
      AllowanceTransaction.mark_as_allowance!(@transaction, current_user)
      notice = "용돈으로 표시되었습니다."
    end

    # 변경된 상태 반영을 위해 reload (association 캐시 포함)
    @transaction = @workspace.transactions
                             .includes(:allowance_transaction, :category, :financial_institution)
                             .find(@transaction.id)

    # turbo_stream 응답을 위한 변수 설정
    @categories = @workspace.categories.order(:name)
    @source = params[:source]
    if @source == "review"
      @parsing_session = @workspace.parsing_sessions.find(params[:parsing_session_id])
      @institutions = FinancialInstitution.all
      @read_only = false
    end

    respond_to do |format|
      format.html { redirect_to workspace_transactions_path(@workspace), notice: notice }
      format.turbo_stream { flash.now[:notice] = notice }
    end
  end

  def quick_update_category
    category_id = params[:category_id].presence
    old_category_id = @transaction.category_id

    @transaction.update(category_id: category_id)
    @categories = @workspace.categories.order(:name)

    # 카테고리가 변경되었으면 매핑 생성
    if category_id.present? && category_id.to_i != old_category_id
      create_category_mapping(@transaction, @transaction.category)
    end

    respond_to do |format|
      format.turbo_stream
      format.json { render json: { success: true } }
    end
  end

  def inline_update
    field = params[:field]
    value = params[:value]

    # Validate field is allowed
    allowed_fields = %w[date merchant description amount notes]
    unless allowed_fields.include?(field)
      head :unprocessable_entity
      return
    end

    # Convert and validate value
    case field
    when "amount"
      value = Integer(value, exception: false)
      if value.nil? || value <= 0
        head :unprocessable_entity
        return
      end
    when "date"
      begin
        value = Date.parse(value)
      rescue ArgumentError, TypeError
        head :unprocessable_entity
        return
      end
    end

    old_category_id = @transaction.category_id

    if @transaction.update(field => value)
      # If merchant or description changed, try to auto-categorize
      if %w[merchant description].include?(field)
        new_category = CategoryMapping.find_category_for_merchant_and_description(
          @workspace,
          @transaction.merchant,
          @transaction.description
        )
        if new_category && new_category.id != old_category_id
          @transaction.update(category: new_category)
        end
      end

      @categories = @workspace.categories.order(:name)
      respond_to do |format|
        format.turbo_stream
      end
    else
      head :unprocessable_entity
    end
  end

  def suggest_category
    merchant = params[:merchant].to_s.strip
    description = params[:description].to_s.strip.presence

    category = CategoryMapping.find_category_for_merchant_and_description(@workspace, merchant, description)

    render json: { category_id: category&.id }
  end

  def export
    transactions = @workspace.transactions.active.includes(:category, :financial_institution)

    if params[:year].present?
      transactions = if params[:month].present?
                       transactions.for_month(params[:year], params[:month])
      else
                       transactions.for_year(params[:year])
      end
    end

    respond_to do |format|
      format.csv do
        send_data generate_csv(transactions),
                  filename: "transactions_#{Date.current}.csv",
                  type: "text/csv; charset=utf-8"
      end
    end
  end

  private

  def set_transaction
    @transaction = @workspace.transactions.find(params[:id])
  end

  def transaction_params
    params.require(:transaction).permit(
      :date, :merchant, :description, :amount, :notes,
      :category_id, :financial_institution_id
    )
  end

  def generate_csv(transactions)
    require "csv"
    CSV.generate(headers: true, encoding: "UTF-8") do |csv|
      csv << [ "날짜", "내역", "금액", "분류", "금융기관", "메모" ]
      transactions.order(date: :desc).each do |tx|
        csv << [
          tx.formatted_date,
          tx.merchant,
          tx.amount,
          tx.category&.name,
          tx.financial_institution&.name,
          tx.notes
        ]
      end
    end
  end

  def create_category_mapping(transaction, category)
    return if transaction.merchant.blank? || category.nil?

    # description이 있으면 description_pattern 포함 매핑 생성, 없으면 기본 매핑
    description_pattern = extract_description_pattern(transaction.description)

    mapping = CategoryMapping.find_or_initialize_by(
      workspace: @workspace,
      merchant_pattern: transaction.merchant,
      description_pattern: description_pattern
    )

    mapping.category = category
    mapping.source = "manual"
    mapping.save!
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn "[TransactionsController] 매핑 생성 실패: #{e.message}"
  end

  def extract_description_pattern(description)
    return nil if description.blank?

    description.strip.presence
  end
end
