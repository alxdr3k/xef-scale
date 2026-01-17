require "test_helper"

class Users::OmniauthCallbacksControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new({
      provider: 'google_oauth2',
      uid: '123456789',
      info: {
        email: 'test@example.com',
        name: 'Test User'
      },
      credentials: {
        token: 'mock_token',
        refresh_token: 'mock_refresh_token',
        expires_at: Time.now + 1.week
      }
    })
  end

  teardown do
    OmniAuth.config.test_mode = false
  end

  test "google_oauth2 callback creates user and signs in" do
    assert_difference 'User.count' do
      post user_google_oauth2_omniauth_callback_path
    end
    assert_redirected_to root_path
    assert_not_nil controller.current_user
  end

  test "google_oauth2 callback signs in existing user" do
    # Create user first
    User.from_omniauth(OmniAuth.config.mock_auth[:google_oauth2])

    assert_no_difference 'User.count' do
      post user_google_oauth2_omniauth_callback_path
    end
    assert_redirected_to root_path
  end

  test "failure callback exists" do
    # Test that the failure method is defined
    controller = Users::OmniauthCallbacksController.new
    assert controller.respond_to?(:failure)
  end
end
