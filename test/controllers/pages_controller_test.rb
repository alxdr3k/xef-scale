require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "landing page for anonymous user" do
    get root_path
    assert_response :success
  end

  test "authenticated user gets dashboard as root" do
    sign_in users(:admin)
    get authenticated_root_path
    assert_response :success
  end
end
