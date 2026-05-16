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
end
