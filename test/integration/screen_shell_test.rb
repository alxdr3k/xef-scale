require "test_helper"

# Phase 1 follow-up (ADR-0003 / ADR-0008): application.html.erb 의 body 골조가
# shared/_screen_shell로 추출되었고, `bg-gray-50` 팔레트 유틸리티가 시맨틱
# 토큰(`bg-page`)으로 교체되었다. 본 테스트는 그 핀을 명시하여 추후 shell
# 리팩토링이 토큰 회귀를 일으키지 않도록 보호한다.
class ScreenShellTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:admin)
    @workspace = workspaces(:main_workspace)
  end

  test "signed-out screen shell uses bg-page token" do
    get new_user_session_path
    assert_response :success
    assert_match(/<body[^>]*class="[^"]*\bbg-page\b/, response.body)
    assert_no_match(/<body[^>]*class="[^"]*\bbg-gray-50\b/, response.body)
  end

  test "signed-in screen shell uses bg-page token and renders navbar" do
    sign_in @user
    get dashboard_path
    assert_response :success
    assert_match(/<body[^>]*class="[^"]*\bbg-page\b/, response.body)
    assert_no_match(/<body[^>]*class="[^"]*\bbg-gray-50\b/, response.body)
    assert_match "지출 추적", response.body
  end

  test "signed-in screen shell renders mobile bottom nav and flash container" do
    sign_in @user
    get dashboard_path
    assert_response :success
    assert_match "mobile-bottom-nav", response.body
    assert_match(/id="flash"/, response.body)
  end

  # 5탭 IA (ADR-0004) — 카테고리 탭은 categories/category_mappings 컨트롤러가
  # admin-only이므로 nav에서도 admin만 노출. 비-admin에게 노출되면 클릭 시
  # `require_workspace_admin_access`가 redirect를 일으켜 dead-end IA 발생.
  test "nav shows 카테고리 tab to workspace admin" do
    sign_in @user
    get dashboard_path
    assert_response :success
    assert_match(/카테고리/, response.body)
  end

  test "nav hides 카테고리 tab from non-admin (member_read) member" do
    sign_in users(:reader)
    get dashboard_path
    assert_response :success
    assert_no_match(/카테고리/, response.body,
                    "카테고리 tab leaked to non-admin (dead-end IA path)")
  end
end
