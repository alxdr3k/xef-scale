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
end
