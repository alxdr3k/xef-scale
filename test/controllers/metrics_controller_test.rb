require "test_helper"

class MetricsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
    @member = users(:member)
    @workspace = workspaces(:main_workspace)
  end

  test "show requires authentication" do
    get workspace_metrics_path(@workspace)
    assert_redirected_to new_user_session_path
  end

  test "show requires workspace admin access (member_read rejected)" do
    sign_in @member
    get workspace_metrics_path(@workspace)
    # require_workspace_admin_access redirects non-admin to workspaces_path.
    assert_response :redirect
  end

  test "show renders metrics report for admin" do
    sign_in @admin
    get workspace_metrics_path(@workspace)
    assert_response :success
    assert_select "h1", text: /검토 메트릭/
    assert_select "pre"
  end

  test "show accepts since/until filters and ignores invalid dates" do
    sign_in @admin
    get workspace_metrics_path(@workspace, since: "2026-01-01", until: "2026-05-18")
    assert_response :success

    # invalid dates → silently ignored (nil), no error
    get workspace_metrics_path(@workspace, since: "not-a-date", until: "also-bad")
    assert_response :success
  end
end
