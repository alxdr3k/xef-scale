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

    assert_no_difference "@workspace.parsing_sessions.where(source_type: 'text_paste').count" do
      post text_parse_workspace_parsing_sessions_path(@workspace),
           params: { text: "신한카드 1,000원 사용 마라탕" }
    end

    assert_redirected_to workspace_parsing_sessions_path(@workspace)
    assert_match(/AI 문자 파싱/, flash[:alert])
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

  # retry action tests
  test "retry rejects non-failed session" do
    post retry_workspace_parsing_session_path(@workspace, @parsing_session)
    assert_redirected_to workspace_parsing_sessions_path(@workspace)
    assert_equal "실패한 세션만 재시도할 수 있습니다.", flash[:alert]
  end

  test "retry on failed file session destroys old session and enqueues job" do
    failed = parsing_sessions(:failed_session)
    processed_file = failed.processed_file
    failed_id = failed.id
    assert_difference "ParsingSession.count", -1 do
      assert_enqueued_with(job: FileParsingJob) do
        post retry_workspace_parsing_session_path(@workspace, failed)
      end
    end
    assert_redirected_to workspace_parsing_sessions_path(@workspace)
    assert_equal "재처리를 시작했습니다.", flash[:notice]
    assert_not ParsingSession.exists?(failed_id)
    assert_equal "pending", processed_file.reload.status
  end

  test "retry on failed text_paste session creates new parsing session and enqueues job" do
    failed = parsing_sessions(:failed_text_session)
    failed_id = failed.id
    # destroy old + create new → net count unchanged
    assert_no_difference "ParsingSession.count" do
      assert_enqueued_with(job: AiTextParsingJob) do
        post retry_workspace_parsing_session_path(@workspace, failed)
      end
    end
    assert_not ParsingSession.exists?(failed_id)
    assert_redirected_to workspace_parsing_sessions_path(@workspace)
    assert_equal "재처리를 시작했습니다.", flash[:notice]
  end

  # destroy action tests
  test "destroy rejects non-failed/non-discarded session" do
    delete workspace_parsing_session_path(@workspace, @parsing_session)
    assert_redirected_to workspace_parsing_sessions_path(@workspace)
    assert_equal "실패하거나 취소된 세션만 삭제할 수 있습니다.", flash[:alert]
  end

  test "destroy deletes failed session" do
    failed = parsing_sessions(:failed_session)
    assert_difference "ParsingSession.count", -1 do
      delete workspace_parsing_session_path(@workspace, failed)
    end
    assert_redirected_to workspace_parsing_sessions_path(@workspace)
    assert_equal "세션이 삭제되었습니다.", flash[:notice]
  end

  test "destroy deletes discarded session" do
    discarded = parsing_sessions(:failed_text_session)
    discarded.update!(review_status: "discarded")
    assert_difference "ParsingSession.count", -1 do
      delete workspace_parsing_session_path(@workspace, discarded)
    end
    assert_redirected_to workspace_parsing_sessions_path(@workspace)
    assert_equal "세션이 삭제되었습니다.", flash[:notice]
  end
end
