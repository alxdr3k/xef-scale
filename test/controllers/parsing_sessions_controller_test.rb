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
    assert_equal "파일을 선택해 주세요.", flash[:alert]
  end

  test "create with file uploads and queues job" do
    file = fixture_file_upload("test_statement.png", "image/png")

    assert_difference "ProcessedFile.count" do
      post workspace_parsing_sessions_path(@workspace), params: { files: [ file ] }
    end
    assert_redirected_to workspace_parsing_sessions_path(@workspace)
    assert_match /파일이 업로드되었습니다/, flash[:notice]
  end

  test "create with multiple files uploads all and queues jobs" do
    file1 = fixture_file_upload("test_statement.png", "image/png")
    file2 = fixture_file_upload("test_statement.png", "image/png")

    assert_difference "ProcessedFile.count", 2 do
      post workspace_parsing_sessions_path(@workspace), params: { files: [ file1, file2 ] }
    end
    assert_redirected_to workspace_parsing_sessions_path(@workspace)
    assert_match /2개 파일이 업로드되었습니다/, flash[:notice]
  end

  test "member with read-only access cannot upload" do
    sign_out @user
    sign_in users(:reader)
    file = fixture_file_upload("test_statement.png", "image/png")

    post workspace_parsing_sessions_path(@workspace), params: { files: [ file ] }
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
    post workspace_parsing_sessions_path(@workspace), params: { files: [ "" ] }
    assert_redirected_to workspace_parsing_sessions_path(@workspace)
  end

  test "text_parse refuses when AI text parsing is disabled" do
    @workspace.update!(ai_text_parsing_enabled: false)

    post text_parse_workspace_parsing_sessions_path(@workspace),
         params: { text: "신한카드 1,000원 사용 마라탕" }

    assert_redirected_to workspace_parsing_sessions_path(@workspace)
    assert_match(/AI 문자 파싱/, flash[:alert])
    assert_equal 0, @workspace.parsing_sessions.where(source_type: "text_paste").count
  end

  test "create refuses when AI image parsing is disabled" do
    @workspace.update!(ai_image_parsing_enabled: false)
    file = fixture_file_upload("test_statement.png", "image/png")

    assert_no_difference "ProcessedFile.count" do
      post workspace_parsing_sessions_path(@workspace), params: { files: [ file ] }
    end

    assert_redirected_to workspace_parsing_sessions_path(@workspace)
    assert_match(/AI 스크린샷 파싱/, flash[:alert])
  end

  test "text_parse refuses when AI consent has not been acknowledged" do
    @workspace.update!(ai_consent_acknowledged_at: nil)

    assert_no_difference "ParsingSession.count" do
      post text_parse_workspace_parsing_sessions_path(@workspace),
           params: { text: "신한카드 1,000원 사용 마라탕" }
    end

    assert_redirected_to settings_workspace_path(@workspace)
    assert_match(/외부 AI 사용 동의/, flash[:alert])
  end

  test "create refuses when AI consent has not been acknowledged" do
    @workspace.update!(ai_consent_acknowledged_at: nil)
    file = fixture_file_upload("test_statement.png", "image/png")

    assert_no_difference "ProcessedFile.count" do
      post workspace_parsing_sessions_path(@workspace), params: { files: [ file ] }
    end

    assert_redirected_to settings_workspace_path(@workspace)
    assert_match(/외부 AI 사용 동의/, flash[:alert])
  end
end
