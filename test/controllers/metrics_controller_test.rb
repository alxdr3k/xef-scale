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
    # Phase 7-2: HTML 카드 — 각 섹션 partial이 렌더되었는지 확인.
    assert_select "h2", text: /요약/
    assert_select "h2", text: /세션 상태 분포/
  end

  test "show accepts since/until filters and ignores invalid dates" do
    sign_in @admin
    get workspace_metrics_path(@workspace, since: "2026-01-01", until: "2026-05-18")
    assert_response :success

    # invalid dates → silently ignored (nil), no error
    get workspace_metrics_path(@workspace, since: "not-a-date", until: "also-bad")
    assert_response :success
  end

  # Codex PR #236 P2: ApplicationController#set_workspace 와 동일한 RecordNotFound
  # rescue 흐름을 metrics에서도 강제 — invalid id 에 대해 404 예외 path 가 아니라
  # workspaces_path 로 redirect.
  test "show with non-member workspace id redirects to workspaces (no 404)" do
    sign_in @admin
    other = workspaces(:other_workspace) # admin은 other_workspace 멤버 아님
    get workspace_metrics_path(other)
    assert_response :redirect
    assert_redirected_to workspaces_path
  end
end
