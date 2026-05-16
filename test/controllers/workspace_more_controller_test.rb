require "test_helper"

class WorkspaceMoreControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:admin)
    @workspace = workspaces(:main_workspace)
    sign_in @user
  end

  test "show requires authentication" do
    sign_out @user
    get workspace_more_path(@workspace)
    assert_redirected_to new_user_session_path
  end

  test "show renders for workspace owner" do
    get workspace_more_path(@workspace)
    assert_response :success
    assert_select "h1", text: @workspace.name
  end

  test "show is reachable by member_read" do
    # ADR-0004 §"필수"와 동일 원칙: 더보기는 read 권한만 요구. 각 항목 클릭 시
    # destination 컨트롤러에서 자체 권한 게이트.
    sign_out @user
    sign_in users(:reader)
    get workspace_more_path(@workspace)
    assert_response :success
  end

  test "show exposes group sections" do
    get workspace_more_path(@workspace)
    assert_response :success
    assert_select "h2", text: "이 워크스페이스"
    assert_select "h2", text: "내 계정"
    assert_select "h2", text: "도구"
  end

  test "위험한 작업 section visible only to admin" do
    get workspace_more_path(@workspace)
    assert_response :success
    assert_match(/위험한 작업/, response.body)

    sign_out @user
    sign_in users(:reader)
    get workspace_more_path(@workspace)
    assert_response :success
    assert_no_match(/위험한 작업/, response.body, "위험한 작업 group이 비-admin에게 노출됨")
  end

  test "settings link visible only to admin" do
    # workspaces#settings는 admin-only. 더보기에서도 admin에게만 링크 노출 — dead-end 방지.
    get workspace_more_path(@workspace)
    assert_includes response.body, settings_workspace_path(@workspace)

    sign_out @user
    sign_in users(:reader)
    get workspace_more_path(@workspace)
    assert_not_includes response.body, settings_workspace_path(@workspace)
  end

  test "denies non-member" do
    sign_out @user
    sign_in users(:other_user) # owner of other_workspace, not main_workspace
    get workspace_more_path(@workspace)
    assert_redirected_to workspaces_path
  end
end
