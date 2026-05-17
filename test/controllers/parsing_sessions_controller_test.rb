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

  # Phase 3.3 (ADR-0004 / preflight §3.1): 입력 폼이 검토함 시트로 이동.
  # parsing_sessions/index 라우트는 *유지*하되 페이지에서는 입력 카드가 없어야 한다.
  # 새로 가져오기는 sheet trigger를 통해서만 진입.
  test "index does not embed inline input form cards (moved to input sheet)" do
    get workspace_parsing_sessions_path(@workspace)
    assert_response :success

    # 폼이 시트 안에는 있지만, "결제 추가" 같은 옛 페이지 헤딩은 제거.
    assert_no_match(/<h1[^>]*>결제 추가</, response.body)
    # 페이지 제목은 "입력 기록"으로 변경.
    assert_select "h1", text: "입력 기록"
  end

  test "index renders input sheet trigger for new imports" do
    get workspace_parsing_sessions_path(@workspace)
    assert_response :success
    assert_select "[data-controller~='input-sheet']", minimum: 1
    assert_select "[data-input-sheet-target='trigger']", minimum: 1
  end

  test "index renders AI consent notice via _inline_alert when consent required" do
    @workspace.update!(ai_consent_acknowledged_at: nil)
    assert @workspace.ai_consent_required?, "setup must produce a consent-required workspace"

    get workspace_parsing_sessions_path(@workspace)
    assert_response :success

    # _inline_alert :warning tone outputs bg-warning-subtle + text-warning +
    # role="status" + aria-live="polite". Pinning these together guards against
    # the alert reverting to a raw amber palette card.
    assert_match "외부 AI 사용 안내", response.body
    assert_select "[role='status'][aria-live='polite']" do
      assert_select "p", text: "외부 AI 사용 안내"
    end
    assert_match "bg-warning-subtle", response.body
  end

  test "index omits AI consent notice when consent is acknowledged" do
    @workspace.update!(ai_consent_acknowledged_at: Time.current)
    refute @workspace.ai_consent_required?

    get workspace_parsing_sessions_path(@workspace)
    assert_response :success
    assert_no_match(/외부 AI 사용 안내/, response.body)
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

  # Phase 5 slice 10: parsing_sessions/index 시맨틱 토큰 마이그레이션.
  test "index view template uses semantic tokens (no hardcoded palette, no undefined tokens)" do
    src = File.read(Rails.root.join("app/views/parsing_sessions/index.html.erb"))
    %w[bg-indigo-600 text-gray-900 text-gray-500 text-gray-700 bg-white bg-blue-50 bg-blue-100].each do |stale|
      assert_no_match(/\b#{Regexp.escape(stale)}\b/, src,
                      "parsing_sessions/index.html.erb에 옛 팔레트 #{stale} 잔존")
    end
    %w[border-default divide-default text-action-strong].each do |undef_token|
      assert_no_match(/\b#{Regexp.escape(undef_token)}\b/, src,
                      "parsing_sessions/index.html.erb에 정의되지 않은 토큰 #{undef_token}")
    end
    assert_match(/\bbg-surface\b/, src)
    assert_match(/\btext-primary\b/, src)
  end
end
