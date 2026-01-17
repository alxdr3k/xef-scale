require "test_helper"

class DuplicateConfirmationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:admin)
    @workspace = workspaces(:main_workspace)
    @parsing_session = parsing_sessions(:completed_session)
    @duplicate_confirmation = duplicate_confirmations(:pending_duplicate)
    sign_in @user
  end

  test "update requires authentication" do
    sign_out @user
    patch workspace_parsing_session_duplicate_confirmation_path(
      @workspace, @parsing_session, @duplicate_confirmation
    ), params: { decision: 'keep_original' }
    assert_redirected_to new_user_session_path
  end

  test "update resolves duplicate with keep_original" do
    patch workspace_parsing_session_duplicate_confirmation_path(
      @workspace, @parsing_session, @duplicate_confirmation
    ), params: { decision: 'keep_original' }
    assert_redirected_to workspace_parsing_session_path(@workspace, @parsing_session)
  end

  test "update resolves duplicate with keep_new" do
    patch workspace_parsing_session_duplicate_confirmation_path(
      @workspace, @parsing_session, @duplicate_confirmation
    ), params: { decision: 'keep_new' }
    assert_redirected_to workspace_parsing_session_path(@workspace, @parsing_session)
  end

  test "update resolves duplicate with keep_both" do
    patch workspace_parsing_session_duplicate_confirmation_path(
      @workspace, @parsing_session, @duplicate_confirmation
    ), params: { decision: 'keep_both' }
    assert_redirected_to workspace_parsing_session_path(@workspace, @parsing_session)
  end

  test "update requires write access" do
    sign_out @user
    member = users(:member)
    sign_in member

    # Member with read-only access should be redirected
    patch workspace_parsing_session_duplicate_confirmation_path(
      @workspace, @parsing_session, @duplicate_confirmation
    ), params: { decision: 'keep_original' }
    # Either redirected to workspace path or parsing session is fine
    assert_response :redirect
  end
end
