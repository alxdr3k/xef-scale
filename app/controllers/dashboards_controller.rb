class DashboardsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace

  def monthly
    @view_type = "monthly"
    @year = params[:year]&.to_i || Date.current.year
    @month = params[:month]&.to_i || Date.current.month

    @transactions = @workspace.transactions
                              .active
                              .for_month(@year, @month)
                              .includes(:category, :financial_institution)
                              .order(date: :desc)

    @total_spending = @transactions.sum(:amount)
    @category_breakdown = build_category_breakdown(@transactions, @total_spending)
    @recent_transactions = @transactions.limit(10)

    render :monthly
  end

  def category_transactions
    @year = params[:year]&.to_i || Date.current.year
    @month = params[:month]&.to_i || Date.current.month
    @category = @workspace.categories.find(params[:category_id])

    @transactions = @workspace.transactions
                              .active
                              .for_month(@year, @month)
                              .where(category_id: @category.id)
                              .includes(:category, :financial_institution)
                              .order(date: :desc)
                              .limit(10)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to monthly_dashboard_path(year: @year, month: @month) }
    end
  end

  def yearly
    @view_type = "yearly"
    @year = params[:year]&.to_i || Date.current.year

    @transactions = @workspace.transactions
                              .active
                              .where(date: Date.new(@year, 1, 1)..Date.new(@year, 12, 31))
                              .includes(:category)

    @total_spending = @transactions.sum(:amount)
    @monthly_average = @total_spending / 12
    @category_breakdown = build_category_breakdown(@transactions, @total_spending)

    # 월별 카테고리 데이터 (차트용)
    @monthly_data = build_monthly_category_data(@year)

    # 월별 총액 계산
    monthly_totals = (1..12).map { |m| @workspace.transactions.active.for_month(@year, m).sum(:amount) }

    # 최고 지출 월
    max_val, max_idx = monthly_totals.each_with_index.max_by { |val, _| val }
    @highest_month = max_val > 0 ? { month: max_idx + 1, amount: max_val } : nil

    # 최저 지출 월 (0보다 큰 월 중에서)
    positive_months = monthly_totals.each_with_index.select { |val, _| val > 0 }
    if positive_months.any?
      min_val, min_idx = positive_months.min_by { |val, _| val }
      @lowest_month = { month: min_idx + 1, amount: min_val }
    else
      @lowest_month = nil
    end

    render :yearly
  end

  private

  def set_workspace
    @workspace = current_workspace
    unless @workspace
      redirect_to new_workspace_path, notice: "먼저 워크스페이스를 생성해 주세요."
    end
  end

  def build_category_breakdown(transactions, total)
    category_totals = transactions.group(:category_id).sum(:amount)
    category_totals.map do |category_id, amount|
      category = Category.find_by(id: category_id)
      {
        id: category_id,
        name: category&.name || "미분류",
        amount: amount,
        color: category&.color || "#9CA3AF",
        percentage: total > 0 ? (amount.to_f / total * 100).round(1) : 0
      }
    end.sort_by { |c| -c[:amount] }
  end

  def build_monthly_category_data(year)
    categories = @workspace.categories.order(:name)

    {
      labels: (1..12).map { |m| "#{m}월" },
      datasets: categories.map do |cat|
        {
          label: cat.name,
          borderColor: cat.color,
          backgroundColor: "#{cat.color}20",
          fill: false,
          tension: 0.3,
          data: (1..12).map { |m|
            @workspace.transactions.active
                      .for_month(year, m)
                      .where(category_id: cat.id)
                      .sum(:amount)
          }
        }
      end.select { |ds| ds[:data].sum > 0 }
    }
  end
end
