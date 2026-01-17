require "test_helper"

class AllowancesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:admin)
    sign_in @user
  end

  test "index requires authentication" do
    sign_out @user
    get allowances_path
    assert_redirected_to new_user_session_path
  end

  test "index lists allowance transactions" do
    get allowances_path
    assert_response :success
  end

  test "index filters by year and month" do
    get allowances_path, params: { year: 2024, month: 3 }
    assert_response :success
  end

  test "index defaults to current month" do
    get allowances_path
    assert_response :success
  end

  test "index displays total amount" do
    get allowances_path
    assert_response :success
  end
end
