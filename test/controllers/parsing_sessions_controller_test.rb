require "test_helper"

class ParsingSessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:admin)
    @workspace = workspaces(:main_workspace)
    @parsing_session = parsing_sessions(:completed_session)
    sign_in @user
  end

  test "index requires authentication" do
    sign_out @user
    get workspace_parsing_sessions_path(@workspace)
    assert_redirected_to new_user_session_path
  end

  test "index lists parsing sessions" do
    get workspace_parsing_sessions_path(@workspace)
    assert_response :success
  end

  test "show redirects to review for completed session" do
    get workspace_parsing_session_path(@workspace, @parsing_session)
    assert_redirected_to review_workspace_parsing_session_path(@workspace, @parsing_session)
  end

  test "create requires file" do
    post workspace_parsing_sessions_path(@workspace)
    assert_redirected_to workspace_parsing_sessions_path(@workspace)
    assert_equal '파일을 선택해 주세요.', flash[:alert]
  end

  test "create with file uploads and queues job" do
    file = fixture_file_upload('test_statement.csv', 'text/csv')

    assert_difference 'ProcessedFile.count' do
      post workspace_parsing_sessions_path(@workspace), params: { file: file }
    end
    assert_redirected_to workspace_parsing_sessions_path(@workspace)
    assert_match /파일이 업로드되었습니다/, flash[:notice]
  end

  test "member with read-only access cannot upload" do
    sign_out @user
    sign_in users(:reader)
    file = fixture_file_upload('test_statement.csv', 'text/csv')

    post workspace_parsing_sessions_path(@workspace), params: { file: file }
    assert_redirected_to workspace_path(@workspace)
  end

  test "show redirects completed session with duplicates to review" do
    session_with_duplicates = parsing_sessions(:completed_session)
    # Create duplicate confirmation if not exists
    unless session_with_duplicates.duplicate_confirmations.any?
      DuplicateConfirmation.create!(
        parsing_session: session_with_duplicates,
        original_transaction: transactions(:food_transaction),
        new_transaction: transactions(:transport_transaction),
        status: "pending"
      )
    end

    get workspace_parsing_session_path(@workspace, session_with_duplicates)
    assert_redirected_to review_workspace_parsing_session_path(@workspace, session_with_duplicates)
  end

  test "create with empty file params fails gracefully" do
    post workspace_parsing_sessions_path(@workspace), params: { file: '' }
    assert_redirected_to workspace_parsing_sessions_path(@workspace)
  end
end
