class TransactionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :require_workspace_access
  before_action :set_transaction, only: [:show, :edit, :update, :destroy, :toggle_allowance]
  before_action :require_workspace_write_access, only: [:new, :create, :edit, :update, :destroy]

  def index
    @year = params[:year].presence&.to_i || Date.current.year
    @month = params[:month].presence&.to_i

    transactions = @workspace.transactions.active.includes(:category, :financial_institution)

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
      respond_to do |format|
        format.html { redirect_to workspace_transactions_path(@workspace), notice: '거래가 추가되었습니다.' }
        format.turbo_stream
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
    if @transaction.update(transaction_params)
      respond_to do |format|
        format.html { redirect_to workspace_transactions_path(@workspace), notice: '거래가 수정되었습니다.' }
        format.turbo_stream
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
      format.html { redirect_to workspace_transactions_path(@workspace), notice: '거래가 삭제되었습니다.' }
      format.turbo_stream
    end
  end

  def toggle_allowance
    if @transaction.allowance?
      AllowanceTransaction.unmark_as_allowance!(@transaction, current_user)
      notice = '용돈에서 제외되었습니다.'
    else
      AllowanceTransaction.mark_as_allowance!(@transaction, current_user)
      notice = '용돈으로 표시되었습니다.'
    end

    respond_to do |format|
      format.html { redirect_to workspace_transactions_path(@workspace), notice: notice }
      format.turbo_stream
    end
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
                  type: 'text/csv; charset=utf-8'
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
    require 'csv'
    CSV.generate(headers: true, encoding: 'UTF-8') do |csv|
      csv << ['날짜', '내역', '금액', '분류', '금융기관', '메모']
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
end
