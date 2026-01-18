class DashboardsController < ApplicationController
  before_action :authenticate_user!

  def show
    @workspace = current_workspace

    if @workspace.nil?
      redirect_to new_workspace_path, notice: '먼저 워크스페이스를 생성해 주세요.'
      return
    end

    @year = params[:year]&.to_i || Date.current.year
    @month = params[:month]&.to_i || Date.current.month

    @transactions = @workspace.transactions
                              .active
                              .for_month(@year, @month)
                              .includes(:category, :financial_institution)
                              .order(date: :desc)

    @total_spending = @transactions.sum(:amount)

    # Get category breakdown with full category objects
    category_totals = @transactions.group(:category_id).sum(:amount)
    @category_breakdown = category_totals.map do |category_id, amount|
      category = Category.find_by(id: category_id)
      {
        name: category&.name || '미분류',
        amount: amount,
        color: category&.color || '#9CA3AF',
        percentage: @total_spending > 0 ? (amount.to_f / @total_spending * 100).round(1) : 0
      }
    end.sort_by { |c| -c[:amount] }

    @recent_transactions = @transactions.limit(10)
  end
end
