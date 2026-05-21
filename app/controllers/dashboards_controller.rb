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
    review_inbox_counts!
    @variance = monthly_variance!(@year, @month, @total_spending)
    recurring_payments_summary!

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

    # Action strip aggregates.
    # Codex PR #248 P2-b/P2-c: action strip 의 "검토 필요 / 중복 의심" 배지는
    # workspace_reviews_path 로 향하므로 그 destination 의 스코프와 일치해야
    # 한다. 이전에는 *이번 달* 전체 pending DuplicateConfirmation/needs_review
    # transaction 을 카운트했지만, 검토함 인덱스는 ParsingSession.needs_review
    # (= completed + pending_review) + workspace-wide 로 보여 준다. 따라서
    # 두 ivar 는 그 스코프에 맞춰 재계산한다.
    #   - 배지 count 가 destination 의 실제 row 수와 일치 → "X 클릭했는데 비어있다" 회피
    #   - finalized 세션의 leftover pending dup 도 destination 에 안 보이므로 같이 제외
    # @needs_review_per_day / @duplicate_per_day 는 calendar grid 셀별 시각화 용도라
    # 월 스코프 그대로 유지 (workspace 전체 카운트는 셀 단위로 의미 없음).
    # 라벨도 calendar.needs_review_count / duplicate_count 에서 "전체" prefix 로
    # workspace-wide 임을 명시 — 월간 칼레더 상단의 시각 문맥과 충돌하지 않게.
    @monthly_total = @daily_totals.values.sum
    @needs_review_total = @workspace.parsing_sessions.needs_review.count
    @duplicate_total = DuplicateConfirmation
                         .pending
                         .joins(:parsing_session)
                         .merge(ParsingSession.needs_review)
                         .where(parsing_sessions: { workspace_id: @workspace.id })
                         .count
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
      redirect_to new_workspace_path, notice: I18n.t("dashboards.flash.workspace_required")
    end
  end

  # Phase 4: 홈 dashboard용 ReviewInboxCard 카운트. ADR-0004 §"필수":
  # `needs_review` scope + DuplicateConfirmation는 parsing_session join으로
  # cross-tenant 스코핑 + finalized 세션 제외 (merge needs_review).
  def review_inbox_counts!
    @pending_review_count = @workspace.parsing_sessions.needs_review.count
    @pending_duplicate_count = DuplicateConfirmation
                                .pending
                                .joins(:parsing_session)
                                .merge(ParsingSession.needs_review)
                                .where(parsing_sessions: { workspace_id: @workspace.id })
                                .count
  end

  # Phase 4 slice 3: monthly에서 노출할 반복 결제 요약. 전체 리스트는
  # `/dashboard/recurring`에 유지 — 카드는 상위 N개 미리보기만.
  RECURRING_PREVIEW_LIMIT = 5

  def recurring_payments_summary!
    patterns = RecurringPaymentDetector.new(@workspace).detect
    @recurring_total_count = patterns.size
    @recurring_monthly_estimate = patterns.sum { |p| p[:average_amount].to_i }
    @recurring_preview = patterns.first(RECURRING_PREVIEW_LIMIT)
  end

  # Phase 4 slice 2: VarianceCard 데이터 (Codex PR #178 후속 fix).
  # 비교 정확성을 위해 *반드시 동일한 일수 window*로 양쪽 누적을 계산한다:
  #   - cutoff_day = min(today.day, prior_month.end.day)
  #   - prior: prior_month 1..cutoff_day 까지 누적
  #   - current: current_month 1..cutoff_day 까지 누적 (`@total_spending` 사용 금지 —
  #     미래일자 commit이 포함되면 부정확)
  #
  # nil 반환 조건 (view 카드 미렌더):
  #   - 보고 있는 month가 `Date.current`의 (year, month)가 아님
  #   - 월의 마지막 날 (페이스 의미 없음)
  #   - prior_total <= 0 (cancellation 등 음수면 분모 sign 뒤집힘 위험)
  def monthly_variance!(year, month, _legacy_total = nil)
    today = Date.current
    return nil unless today.year == year && today.month == month

    start_of_month = Date.new(year, month, 1)
    end_of_month = start_of_month.end_of_month
    return nil if today.day >= end_of_month.day

    prior_start = start_of_month.prev_month
    prior_end_of_month = prior_start.end_of_month
    # 두 기간을 같은 일수로 정렬. prior가 짧으면 current도 cutoff_day까지만.
    cutoff_day = [ today.day, prior_end_of_month.day ].min

    current_cutoff = Date.new(year, month, cutoff_day)
    prior_cutoff   = prior_start + (cutoff_day - 1)

    current_mtd_total = @workspace.transactions
                                  .active
                                  .excluding_coupon
                                  .where(date: start_of_month..current_cutoff)
                                  .sum(:amount)
    prior_total = @workspace.transactions
                            .active
                            .excluding_coupon
                            .where(date: prior_start..prior_cutoff)
                            .sum(:amount)

    return nil if prior_total <= 0

    variance_pct = (((current_mtd_total - prior_total).to_f / prior_total) * 100).round
    projected_end = ((current_mtd_total.to_f / cutoff_day) * end_of_month.day).round

    {
      prior_total: prior_total,
      current_total: current_mtd_total,
      variance_pct: variance_pct,
      projected_end: projected_end,
      compared_until_day: cutoff_day
    }
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
        name: category&.name || I18n.t("dashboards.uncategorized"),
        amount: amount,
        color: category&.color || "#9CA3AF",
        percentage: total > 0 ? (amount.to_f / total * 100).round(1) : 0
      }
    end.sort_by { |c| -c[:amount] }
  end

  def build_monthly_category_data(year)
    categories = @workspace.categories.order(:name)

    {
      labels: (1..12).map { |m| I18n.t("dashboards.month_label", month: m) },
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
