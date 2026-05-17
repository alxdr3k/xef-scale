require "test_helper"

class DashboardsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:admin)
    @workspace = workspaces(:main_workspace)
    sign_in @user
  end

  test "show requires authentication" do
    sign_out @user
    get dashboard_path
    assert_redirected_to new_user_session_path
  end

  test "show redirects to new workspace if no workspace" do
    @user.workspace_memberships.destroy_all
    get dashboard_path
    assert_redirected_to new_workspace_path
  end

  test "show displays dashboard" do
    get dashboard_path
    assert_response :success
  end

  test "show filters by year and month" do
    get dashboard_path, params: { year: 2024, month: 1 }
    assert_response :success
  end

  test "show defaults to current month" do
    get dashboard_path
    assert_response :success
  end

  test "show renders dashboard page" do
    get dashboard_path
    assert_response :success
  end

  test "monthly view displays recent transactions section" do
    get monthly_dashboard_path
    assert_response :success
    assert_select "h2", text: /최근 결제/
  end

  test "dashboard ignores out-of-range month param instead of 500ing" do
    get dashboard_path, params: { year: 2024, month: 13 }
    assert_response :success
  end

  test "dashboard ignores non-integer date params" do
    get dashboard_path, params: { year: "abc", month: "xyz" }
    assert_response :success
  end

  test "yearly dashboard ignores out-of-range year param" do
    get yearly_dashboard_path, params: { year: 999_999 }
    assert_response :success
  end

  test "monthly dashboard daily average divides by full month for past months" do
    past = Date.current - 2.months
    @workspace.transactions.create!(
      date: Date.new(past.year, past.month, 5),
      amount: 30_000,
      status: "committed"
    )

    get monthly_dashboard_path, params: { year: past.year, month: past.month }

    assert_response :success
    expected_denominator = Date.new(past.year, past.month, 1).end_of_month.day
    expected_average = 30_000 / expected_denominator
    assert_equal expected_denominator, controller.instance_variable_get(:@daily_average_denominator)
    assert_equal expected_average, controller.instance_variable_get(:@daily_average)
  end

  test "monthly dashboard daily average uses today's day for the current month" do
    @workspace.transactions.create!(
      date: Date.current,
      amount: 7_000,
      status: "committed"
    )

    get monthly_dashboard_path, params: { year: Date.current.year, month: Date.current.month }

    assert_response :success
    assert_equal Date.current.day, controller.instance_variable_get(:@daily_average_denominator)
  end

  test "calendar dashboard renders for the current month" do
    get calendar_dashboard_path
    assert_response :success
    assert_select "h1", text: /대시보드/
  end

  test "calendar dashboard groups daily totals" do
    target = Date.current.beginning_of_month + 4.days
    @workspace.transactions.create!(date: target, amount: 12_000, status: "committed")

    get calendar_dashboard_path, params: { year: target.year, month: target.month, date: target.to_s }

    assert_response :success
    daily_totals = controller.instance_variable_get(:@daily_totals)
    assert_equal 12_000, daily_totals[target]
    assert_equal target, controller.instance_variable_get(:@selected_date)
  end

  test "calendar dashboard ignores out-of-range month param" do
    get calendar_dashboard_path, params: { year: 2024, month: 13 }
    assert_response :success
  end

  test "calendar dashboard counts pending duplicate confirmations per day" do
    target = Date.current.beginning_of_month + 4.days
    session = @workspace.parsing_sessions.create!(
      source_type: "text_paste",
      status: "completed",
      review_status: "pending_review"
    )
    original = @workspace.transactions.create!(
      date: target,
      amount: 5_000,
      merchant: "스타벅스",
      status: "committed"
    )
    new_tx = @workspace.transactions.create!(
      date: target,
      amount: 5_000,
      merchant: "스타벅스",
      status: "pending_review",
      parsing_session: session
    )
    DuplicateConfirmation.create!(
      parsing_session: session,
      original_transaction: original,
      new_transaction: new_tx,
      status: "pending"
    )

    get calendar_dashboard_path, params: { year: target.year, month: target.month }

    assert_response :success
    duplicate_per_day = controller.instance_variable_get(:@duplicate_per_day)
    assert_equal 1, duplicate_per_day[target]
  end

  test "calendar dashboard does not surface financial institution names" do
    target = transactions(:food_transaction).date

    get calendar_dashboard_path, params: { year: target.year, month: target.month, date: target.to_s }

    assert_response :success
    assert_includes response.body, transactions(:food_transaction).merchant
    assert_not_includes response.body, financial_institutions(:shinhan_card).name
  end

  test "calendar dashboard duplicate counts ignore resolved confirmations" do
    target = Date.current.beginning_of_month + 5.days
    session = @workspace.parsing_sessions.create!(
      source_type: "text_paste",
      status: "completed",
      review_status: "pending_review"
    )
    original = @workspace.transactions.create!(
      date: target, amount: 3_200, merchant: "CU", status: "committed"
    )
    new_tx = @workspace.transactions.create!(
      date: target, amount: 3_200, merchant: "CU", status: "pending_review",
      parsing_session: session
    )
    DuplicateConfirmation.create!(
      parsing_session: session,
      original_transaction: original,
      new_transaction: new_tx,
      status: "keep_new"
    )

    get calendar_dashboard_path, params: { year: target.year, month: target.month }

    assert_response :success
    duplicate_per_day = controller.instance_variable_get(:@duplicate_per_day)
    assert_nil duplicate_per_day[target]
  end

  test "monthly dashboard daily average is hidden for future months" do
    future = Date.current.next_month.next_month

    get monthly_dashboard_path, params: { year: future.year, month: future.month }

    assert_response :success
    assert_equal 0, controller.instance_variable_get(:@daily_average_denominator)
    assert_select "span", text: /일 평균/, count: 0
  end

  # Phase 4: Hero stat + ReviewInboxCard 채택 검증.
  test "monthly dashboard adopts shared/_hero_stat (semantic tokens, no indigo gradient)" do
    get monthly_dashboard_path
    assert_response :success
    # 옛 hero는 `bg-indigo-600 rounded-2xl shadow-lg` 조합으로 인디고 그라데이션
    # block을 만들었음 — 그 조합이 사라졌는지 확인.
    assert_no_match(/bg-indigo-600\s+rounded-2xl\s+shadow-lg/, response.body)
    # 신규 hero는 shared/_hero_stat: bg-surface section + text-secondary label.
    assert_match(/<section[^>]*bg-surface[^>]*>\s*<p[^>]*text-secondary[^>]*>[^<]*총 지출/m, response.body)
  end

  test "monthly dashboard renders ReviewInboxCard when pending items exist" do
    session = @workspace.parsing_sessions.create!(
      source_type: "text_paste", status: "completed",
      review_status: "pending_review",
      total_count: 1, success_count: 1, duplicate_count: 0, error_count: 0
    )
    @workspace.transactions.create!(
      date: Date.current, amount: 1000, merchant: "REVIEW_INBOX_HOME",
      status: "pending_review", parsing_session: session
    )

    get monthly_dashboard_path
    assert_response :success
    assert_match(/검토 대기/, response.body)
    assert_includes response.body, workspace_reviews_path(@workspace)
  end

  test "monthly dashboard omits ReviewInboxCard when no pending items" do
    @workspace.parsing_sessions.where(status: "completed", review_status: "pending_review")
              .find_each { |s| s.update!(review_status: "committed") }
    DuplicateConfirmation.joins(:parsing_session)
                         .where(parsing_sessions: { workspace_id: @workspace.id })
                         .find_each(&:destroy)

    get monthly_dashboard_path
    assert_response :success
    # 검토함 진입 CTA가 없음 (카드 자체 미렌더).
    assert_no_match(/지금 검토/, response.body)
  end

  # Phase 4 slice 2: VarianceCard 데이터 흐름.
  test "monthly_variance returns nil when viewing a non-current month" do
    @workspace.transactions.create!(
      date: 2.months.ago.beginning_of_month, amount: 5000, merchant: "OLD"
    )
    # 2개월 전 month로 직접 진입 — today와 month가 다르므로 variance nil.
    past = 2.months.ago
    get monthly_dashboard_path, params: { year: past.year, month: past.month }
    assert_response :success
    assert_nil controller.instance_variable_get(:@variance)
  end

  test "monthly_variance returns nil when prior month has no spending" do
    # 현재 month 데이터는 있지만 전월 spending 0 → 비교 불가.
    Transaction.where(workspace: @workspace).destroy_all
    @workspace.transactions.create!(
      date: Date.current, amount: 10_000, merchant: "NOW"
    )
    get monthly_dashboard_path
    assert_response :success
    assert_nil controller.instance_variable_get(:@variance)
  end

  test "monthly_variance computes variance_pct and projected_end" do
    Transaction.where(workspace: @workspace).destroy_all
    today = Date.current
    skip "today is end-of-month; variance skips projection" if today == today.end_of_month
    # Codex PR #178 P1: prior month가 짧을 때(예: 3월 29일 vs 2월 28일) cutoff_day가
    # prior_end_day로 clamp되어 today 거래가 제외됨. 이 테스트는 today 거래가
    # cutoff 안에 포함되는 케이스만 검증한다.
    skip "today.day exceeds prior month length" if today.day > today.prev_month.end_of_month.day

    prior_month_same_day_start = today.prev_month.beginning_of_month
    @workspace.transactions.create!(
      date: prior_month_same_day_start, amount: 10_000, merchant: "PRIOR"
    )
    @workspace.transactions.create!(
      date: today, amount: 20_000, merchant: "CURRENT"
    )

    get monthly_dashboard_path
    assert_response :success
    variance = controller.instance_variable_get(:@variance)
    assert_not_nil variance
    assert_equal 10_000, variance[:prior_total]
    assert_equal 20_000, variance[:current_total]
    assert_equal 100, variance[:variance_pct], "current가 prior의 2배 → +100%"
    expected_projected = ((20_000.to_f / today.day) * today.end_of_month.day).round
    assert_equal expected_projected, variance[:projected_end]
    # 비교 기간 표시
    assert_equal today.day, variance[:compared_until_day]
    # 화면에 노출
    assert_match(/지난달 같은 시점 대비/, response.body)
    assert_match(/▲ 100%/, response.body)
  end

  # Phase 5 slice 11: dashboards/calendar 시맨틱 토큰 마이그레이션 회귀 차단.
  # Codex PR #207 P2/P3: ring-indigo / border-indigo도 가드. Stimulus controller
  # (calendar_controller.js)도 함께 검사 — interactive class toggle도 시맨틱
  # 토큰을 써야 템플릿 초기 selected와 mismatch가 안 난다.
  test "calendar view + Stimulus use semantic tokens (no hardcoded palette, no undefined tokens)" do
    template = File.read(Rails.root.join("app/views/dashboards/calendar.html.erb"))
    controller = File.read(Rails.root.join("app/javascript/controllers/calendar_controller.js"))
    sources = { "calendar.html.erb" => template, "calendar_controller.js" => controller }

    stale_palette = %w[
      bg-indigo-600 ring-indigo-600 border-indigo-600 border-indigo-300
      text-gray-900 text-gray-500 text-gray-700 bg-white
      bg-red-50 bg-amber-50 bg-red-100 bg-amber-100
    ]
    sources.each do |name, src|
      stale_palette.each do |stale|
        assert_no_match(/\b#{Regexp.escape(stale)}\b/, src,
                        "#{name}에 옛 팔레트 #{stale} 잔존")
      end
    end

    %w[border-default divide-default text-action-strong].each do |undef_token|
      assert_no_match(/\b#{Regexp.escape(undef_token)}\b/, template,
                      "calendar.html.erb에 정의되지 않은 토큰 #{undef_token}")
    end
    assert_match(/\bbg-surface\b/, template)
    assert_match(/\btext-primary\b/, template)
    # Stimulus도 시맨틱 토큰을 토글해야 템플릿 초기 selected와 일치.
    assert_match(/\b(border|ring)-action\b/, controller)
  end

  test "variance card uses positive tone when spending decreased" do
    Transaction.where(workspace: @workspace).destroy_all
    today = Date.current
    skip if today == today.end_of_month
    # Codex PR #178 P1: cutoff_day clamp로 today 거래가 제외될 수 있음.
    skip "today.day exceeds prior month length" if today.day > today.prev_month.end_of_month.day

    @workspace.transactions.create!(
      date: today.prev_month.beginning_of_month, amount: 20_000, merchant: "PRIOR"
    )
    @workspace.transactions.create!(
      date: today, amount: 10_000, merchant: "CURRENT"
    )

    get monthly_dashboard_path
    assert_response :success
    # decreased = positive tone (ADR-0006 의미축: 지출 감소가 긍정).
    assert_match(/text-positive[^<]*▼ 50%/m, response.body)
  end

  # Codex PR #178: variance가 month-to-date만 사용해야 함 (미래일자 commit 제외).
  test "monthly_variance excludes future-dated current-month transactions from current_total" do
    Transaction.where(workspace: @workspace).destroy_all
    today = Date.current
    skip if today == today.end_of_month
    # Codex PR #178 P1: cutoff_day clamp로 today 거래가 제외되는 calendar 경계 회피.
    skip "today.day exceeds prior month length" if today.day > today.prev_month.end_of_month.day

    @workspace.transactions.create!(
      date: today.prev_month.beginning_of_month, amount: 10_000, merchant: "PRIOR"
    )
    @workspace.transactions.create!(
      date: today, amount: 10_000, merchant: "TODAY"
    )
    # 미래일자 거래 — variance가 잘못 포함하면 anomaly.
    @workspace.transactions.create!(
      date: today + 5.days, amount: 50_000, merchant: "FUTURE_INFLATE"
    )

    get monthly_dashboard_path
    assert_response :success
    variance = controller.instance_variable_get(:@variance)
    assert_not_nil variance
    assert_equal 10_000, variance[:current_total],
                 "미래일자 거래(₩50,000)가 current_total에 포함되면 안 됨"
    assert_equal 0, variance[:variance_pct], "today까지만 비교하면 prior와 동일 → 0%"
  end

  # Codex PR #178: prior month가 짧을 때 두 기간을 같은 cutoff_day로 정렬.
  test "monthly_variance aligns prior and current windows when prior month is shorter" do
    Transaction.where(workspace: @workspace).destroy_all
    today = Date.current
    skip if today == today.end_of_month
    prior_end_day = today.prev_month.end_of_month.day

    # today.day가 prior month last day보다 작으면 정렬 effect가 없으므로 가정 skip.
    skip "prior month length not shorter than today.day in this scenario" if today.day <= prior_end_day

    # 양쪽 동일 prefix(day=1)에만 거래 → 정렬되면 같은 amount.
    @workspace.transactions.create!(
      date: today.prev_month.beginning_of_month, amount: 5_000, merchant: "PRIOR"
    )
    @workspace.transactions.create!(
      date: today.beginning_of_month, amount: 5_000, merchant: "CURRENT_DAY_1"
    )
    # current month의 *prior_end_day 이후* 거래 — clamp로 제외돼야.
    @workspace.transactions.create!(
      date: today, amount: 100_000, merchant: "CURRENT_PAST_PRIOR_END"
    )

    get monthly_dashboard_path
    assert_response :success
    variance = controller.instance_variable_get(:@variance)
    assert_not_nil variance
    assert_equal prior_end_day, variance[:compared_until_day],
                 "cutoff_day = min(today.day, prior_end_day) = prior_end_day"
    assert_equal 5_000, variance[:prior_total]
    assert_equal 5_000, variance[:current_total],
                 "cutoff_day 이후 거래는 정렬로 제외돼야"
  end

  # Phase 4 slice 3: RecurringPaymentCard.
  test "monthly dashboard renders RecurringPaymentCard when patterns detected" do
    Transaction.where(workspace: @workspace).destroy_all
    today = Date.current
    # 2개월 연속 동일 merchant — MIN_OCCURRENCES=2 충족.
    @workspace.transactions.create!(
      date: today.prev_month.beginning_of_month, amount: 11_000, merchant: "넷플릭스"
    )
    @workspace.transactions.create!(
      date: today, amount: 11_000, merchant: "넷플릭스"
    )

    get monthly_dashboard_path
    assert_response :success
    assert_match(/반복 결제/, response.body)
    assert_includes response.body, "넷플릭스"
    # CTA가 recurring 상세 페이지로 이동.
    assert_includes response.body, recurring_dashboard_path
  end

  test "monthly dashboard omits RecurringPaymentCard when no patterns" do
    Transaction.where(workspace: @workspace).destroy_all
    @workspace.transactions.create!(
      date: Date.current, amount: 5_000, merchant: "ONE_OFF"
    )

    get monthly_dashboard_path
    assert_response :success
    # 반복 결제 카드 자체가 없음 — h2 "반복 결제"가 미렌더.
    assert_select "h2", text: "반복 결제", count: 0
  end

  # Codex PR #178: prior_total ≤ 0 (cancellation 등) 가드.
  test "monthly_variance returns nil when prior_total is negative" do
    Transaction.where(workspace: @workspace).destroy_all
    today = Date.current
    skip if today == today.end_of_month
    # prior month 시작일은 항상 day=1이므로 cutoff_day=1 이상 보장 — short month
    # 영향은 없으나 일관성을 위해 가드.
    skip "today.day exceeds prior month length" if today.day > today.prev_month.end_of_month.day

    # prior month에 large refund (negative). 합산 음수가 되도록.
    @workspace.transactions.create!(
      date: today.prev_month.beginning_of_month, amount: 5_000, merchant: "OLD_BUY"
    )
    @workspace.transactions.create!(
      date: today.prev_month.beginning_of_month, amount: -20_000, merchant: "OLD_REFUND"
    )
    @workspace.transactions.create!(
      date: today, amount: 10_000, merchant: "CURRENT"
    )

    get monthly_dashboard_path
    assert_response :success
    assert_nil controller.instance_variable_get(:@variance),
               "prior_total <= 0이면 분모 sign 뒤집힘 → 카드 자체 미렌더"
  end
end
