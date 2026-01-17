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
    @category_breakdown = @transactions.group(:category_id)
                                       .sum(:amount)
                                       .transform_keys { |id| Category.find_by(id: id)&.name || '미분류' }

    @recent_transactions = @transactions.limit(10)
  end
end
