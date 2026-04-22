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

  test "show displays recent transactions section" do
    get dashboard_path
    assert_response :success
    assert_select "h2", text: /최근 거래/
  end

  test "monthly dashboard ignores out-of-range month param instead of 500ing" do
    get dashboard_path, params: { year: 2024, month: 13 }
    assert_response :success
  end

  test "monthly dashboard ignores non-integer date params" do
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

    get dashboard_path, params: { year: past.year, month: past.month }

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

    get dashboard_path, params: { year: Date.current.year, month: Date.current.month }

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

  test "monthly dashboard daily average is hidden for future months" do
    future = Date.current.next_month.next_month

    get dashboard_path, params: { year: future.year, month: future.month }

    assert_response :success
    assert_equal 0, controller.instance_variable_get(:@daily_average_denominator)
    assert_select "span", text: /일 평균/, count: 0
  end
end
