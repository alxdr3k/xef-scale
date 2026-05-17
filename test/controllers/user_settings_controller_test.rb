require "test_helper"

class UserSettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:admin)
    sign_in @user
  end

  test "show requires authentication" do
    sign_out @user
    get user_settings_path
    assert_redirected_to new_user_session_path
  end

  test "show renders" do
    get user_settings_path
    assert_response :success
  end

  # Phase 5: theme 변경 저장.
  test "update persists theme to user settings JSON" do
    @user.update!(settings: { "theme" => "auto" })

    patch user_settings_path, params: { user: { theme: "dark" } }

    assert_redirected_to user_settings_path
    assert_equal "dark", @user.reload.theme
  end

  test "update normalizes invalid theme to auto" do
    patch user_settings_path, params: { user: { theme: "neon" } }

    assert_redirected_to user_settings_path
    assert_equal "auto", @user.reload.theme
  end

  test "update keeps existing theme when not submitted" do
    @user.update!(settings: { "theme" => "dark" })

    patch user_settings_path, params: { user: { excluded_merchants: "스타벅스" } }

    assert_redirected_to user_settings_path
    assert_equal "dark", @user.reload.theme,
                 "theme이 폼에 없으면 기존 값 보존"
  end
end
