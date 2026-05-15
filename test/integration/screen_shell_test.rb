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
end
