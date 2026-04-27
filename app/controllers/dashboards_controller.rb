class DashboardsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace

  def monthly
    @view_type = "monthly"
    @year = sanitize_year(params[:year]) || Date.current.year
    @month = sanitize_month(params[:month]) || Date.current.month

    @transactions = @workspace.transactions
                              .active
                              .for_month(@year, @month)
                              .includes(:category)
                              .order(date: :desc)

    @total_spending = @transactions.excluding_coupon.sum(:amount)
    @category_breakdown = build_category_breakdown(@transactions.excluding_coupon, @total_spending)
    @recent_transactions = @transactions.limit(10)
    @budget = @workspace.budget
    @budget_progress = @budget&.progress_for_month(@year, @month)
    @daily_average_denominator = daily_average_denominator(@year, @month)
    @daily_average = @daily_average_denominator.zero? ? 0 : (@total_spending / @daily_average_denominator)

    render :monthly
  end

  def category_transactions
    @year = sanitize_year(params[:year]) || Date.current.year
    @month = sanitize_month(params[:month]) || Date.current.month
    @category = @workspace.categories.find(params[:category_id])

    @transactions = @workspace.transactions
                              .active
                              .for_month(@year, @month)
                              .where(category_id: @category.id)
                              .includes(:category)
                              .order(date: :desc)
                              .limit(10)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to monthly_dashboard_path(year: @year, month: @month) }
    end
  end

  def yearly
    @view_type = "yearly"
    @year = sanitize_year(params[:year]) || Date.current.year

    @transactions = @workspace.transactions
                              .active
                              .where(date: Date.new(@year, 1, 1)..Date.new(@year, 12, 31))
                              .includes(:category)

    @total_spending = @transactions.excluding_coupon.sum(:amount)
    @monthly_average = @total_spending / 12
    @category_breakdown = build_category_breakdown(@transactions.excluding_coupon, @total_spending)

    # 월별 카테고리 데이터 (차트용)
    @monthly_data = build_monthly_category_data(@year)

    # 월별 총액 계산
    monthly_totals = (1..12).map { |m| @workspace.transactions.active.excluding_coupon.for_month(@year, m).sum(:amount) }

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

  def recurring
    @view_type = "recurring"
    detector = RecurringPaymentDetector.new(@workspace)
    @recurring_patterns = detector.detect
  end

  def calendar
    @view_type = "calendar"
    @year = sanitize_year(params[:year]) || Date.current.year
    @month = sanitize_month(params[:month]) || Date.current.month

    start_date = Date.new(@year, @month, 1)
    end_date = start_date.end_of_month

    daily_totals = @workspace.transactions
                             .active
                             .excluding_coupon
                             .where(date: start_date..end_date)
                             .group(:date)
                             .sum(:amount)
    @daily_totals = daily_totals.transform_keys { |d| d.is_a?(String) ? Date.parse(d) : d }

    @needs_review_per_day = @workspace.parsing_sessions
                                      .needs_review
                                      .joins(:transactions)
                                      .where(transactions: { date: start_date..end_date, deleted: false })
                                      .where.not(transactions: { status: "rolled_back" })
                                      .group("transactions.date")
                                      .count("DISTINCT transactions.id")
                                      .transform_keys { |d| d.is_a?(String) ? Date.parse(d) : d }

    # Use an explicit alias so the query stays correct even if a future
    # change joins the transactions table a second time (e.g. via
    # :original_transaction). Without the alias Rails may silently rename
    # the :new_transaction join and break the `transactions.date`
    # reference.
    @duplicate_per_day = DuplicateConfirmation
                           .joins(:parsing_session)
                           .joins("INNER JOIN transactions AS new_transactions ON new_transactions.id = duplicate_confirmations.new_transaction_id")
                           .where(parsing_sessions: { workspace_id: @workspace.id })
                           .where(status: "pending")
                           .where("new_transactions.date BETWEEN ? AND ?", start_date, end_date)
                           .group("new_transactions.date")
                           .count
                           .transform_keys { |d| d.is_a?(String) ? Date.parse(d) : d }

    @uncategorized_per_day = @workspace.transactions
                                       .active
                                       .where(date: start_date..end_date, category_id: nil)
                                       .group(:date)
                                       .count
                                       .transform_keys { |d| d.is_a?(String) ? Date.parse(d) : d }

    @calendar_weeks = build_calendar_weeks(start_date, end_date)
    @selected_date = sanitize_date(params[:date]) || Date.current
    @selected_date = start_date if @selected_date < start_date || @selected_date > end_date

    @selected_day_transactions = @workspace.transactions
                                           .active
                                           .where(date: @selected_date)
                                           .includes(:category)
                                           .order(created_at: :desc)

    # Action strip aggregates
    @monthly_total = @daily_totals.values.sum
    @needs_review_total = @needs_review_per_day.values.sum
    @duplicate_total = @duplicate_per_day.values.sum
    @uncategorized_total = @uncategorized_per_day.values.sum
  end

  def calendar_day
    @date = sanitize_date(params[:date]) || Date.current
    @selected_day_transactions = @workspace.transactions
                                           .active
                                           .where(date: @date)
                                           .includes(:category)
                                           .order(created_at: :desc)

    respond_to do |format|
      format.html
    end
  end

  private

  def set_workspace
    @workspace = current_workspace
    unless @workspace
      redirect_to new_workspace_path, notice: "먼저 워크스페이스를 생성해 주세요."
    end
  end

  def sanitize_date(value)
    return nil if value.blank?
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def build_calendar_weeks(start_date, end_date)
    grid_start = start_date.beginning_of_week(:sunday)
    grid_end = end_date.end_of_week(:sunday)
    (grid_start..grid_end).each_slice(7).to_a
  end

  # Days that have already happened in the selected month. For the current
  # month that's today's day-of-month; for past months it's the full month;
  # for future months no spending has accrued yet so we return 0 (callers
  # must guard against division by zero).
  def daily_average_denominator(year, month)
    today = Date.current
    selected = Date.new(year, month, 1)
    if selected.year == today.year && selected.month == today.month
      today.day
    elsif selected < today.beginning_of_month
      selected.end_of_month.day
    else
      0
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
