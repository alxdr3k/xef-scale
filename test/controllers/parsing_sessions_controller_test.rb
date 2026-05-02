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

  test "index shows failed incomplete parser note without internal markers" do
    note = "자동 반영 제외 1건\n1. 누락: 날짜 - 네이버페이 / 12,000원"
    parsing_sessions(:failed_session).update!(
      source_type: "file_upload",
      notes: ParsingSession.incomplete_parse_note_block(note)
    )

    get workspace_parsing_sessions_path(@workspace)

    assert_response :success
    assert_includes response.body, "네이버페이"
    assert_not_includes response.body, ParsingSession::INCOMPLETE_PARSE_NOTE_START_MARKER
  end

  test "index links failed sessions with import issues" do
    session = parsing_sessions(:failed_session)
    session.import_issues.create!(
      workspace: @workspace,
      source_type: "image_upload",
      merchant: "마차이짬뽕 성수점",
      amount: 61_000,
      missing_fields: [ "date" ]
    )

    get workspace_parsing_sessions_path(@workspace)

    assert_response :success
    assert_includes response.body, "수정 필요 1건"
    assert_select "a", text: "상세보기", minimum: 1
  end

  test "index duplicate filter includes ambiguous duplicate import issues" do
    session = @workspace.parsing_sessions.create!(
      source_type: "text_paste",
      status: "completed",
      review_status: "pending_review"
    )
    duplicate = @workspace.transactions.create!(
      date: Date.current,
      merchant: "스타벅스강남점",
      amount: 5_000,
      status: "committed"
    )
    session.import_issues.create!(
      workspace: @workspace,
      source_type: "text_paste",
      issue_type: "ambiguous_duplicate",
      duplicate_transaction: duplicate,
      date: duplicate.date,
      merchant: "스타벅스 강남",
      amount: duplicate.amount,
      missing_fields: []
    )

    get workspace_parsing_sessions_path(@workspace),
        params: { filter: "has_duplicates", year: duplicate.date.year, month: duplicate.date.month }

    assert_response :success
    assert_includes response.body, "중복 1건"
    assert_select "a[href='#{workspace_transactions_path(@workspace, repair: "required", import_session_id: session.id)}']", text: "수정하기"
  end

  test "month scoped needs review includes repair-only import issue sessions" do
    target = Date.current.beginning_of_month + 3.days
    session = @workspace.parsing_sessions.create!(
      source_type: "file_upload",
      status: "completed",
      review_status: "pending_review"
    )
    session.import_issues.create!(
      workspace: @workspace,
      source_type: "image_upload",
      issue_type: "missing_required_fields",
      date: target,
      merchant: "날짜 있는 누락 항목",
      amount: 12_000,
      missing_fields: [ "merchant" ]
    )

    get workspace_parsing_sessions_path(@workspace),
        params: { filter: "needs_review", year: target.year, month: target.month }

    assert_response :success
    assert_includes response.body, "수정하기"
    assert_select "a[href='#{workspace_transactions_path(@workspace, repair: "required", import_session_id: session.id)}']", text: "수정하기"
  end

  test "month scoped index includes exact duplicate only sessions by created month outside duplicate filter" do
    target = Time.zone.local(Date.current.year, Date.current.month, 15, 12, 0, 0)
    session = @workspace.parsing_sessions.create!(
      source_type: "text_paste",
      status: "completed",
      review_status: "committed",
      total_count: 1,
      success_count: 0,
      duplicate_count: 1,
      error_count: 0,
      created_at: target
    )

    get workspace_parsing_sessions_path(@workspace),
        params: { year: target.year, month: target.month }

    assert_response :success
    assert_includes response.body, "##{session.id}"

    get workspace_parsing_sessions_path(@workspace),
        params: { filter: "has_duplicates", year: target.year, month: target.month }

    assert_response :success
    assert_not_includes response.body, "##{session.id}"
  end

  test "month scoped index includes undated import issue sessions by created month" do
    target = Time.zone.local(Date.current.year, Date.current.month, 16, 12, 0, 0)
    session = @workspace.parsing_sessions.create!(
      source_type: "file_upload",
      status: "completed",
      review_status: "pending_review",
      created_at: target
    )
    session.import_issues.create!(
      workspace: @workspace,
      source_type: "image_upload",
      issue_type: "missing_required_fields",
      date: nil,
      merchant: "날짜 없는 누락 항목",
      amount: 12_000,
      missing_fields: [ "date" ]
    )

    get workspace_parsing_sessions_path(@workspace),
        params: { year: target.year, month: target.month }

    assert_response :success
    assert_includes response.body, "수정하기"
    assert_select "a[href='#{workspace_transactions_path(@workspace, repair: "required", import_session_id: session.id)}']", text: "수정하기"
  end

  test "show renders failed import issue details" do
    session = parsing_sessions(:failed_session)
    session.import_issues.create!(
      workspace: @workspace,
      source_type: "image_upload",
      merchant: "네이버페이",
      amount: 12_000,
      missing_fields: [ "date" ],
      raw_payload: { "merchant" => "네이버페이" }
    )

    get workspace_parsing_session_path(@workspace, session)

    assert_response :success
    assert_select "p", text: "자동 반영되지 않은 항목이 있습니다", count: 1
    assert_includes response.body, "누락: 날짜"
    assert_includes response.body, "네이버페이"
    assert_includes response.body, "12,000원"
  end

  test "index hides AI input panels while consent is required" do
    @workspace.update!(ai_consent_acknowledged_at: nil)

    get workspace_parsing_sessions_path(@workspace)

    assert_response :success
    assert_select "textarea#text", count: 0
    assert_select "input[type='file']", count: 0
    assert_select "a", text: /워크스페이스 설정에서 동의 또는 비활성화/
    assert_select "h2", text: "입력 기록"
  end

  test "index shows AI input panels after consent is acknowledged" do
    get workspace_parsing_sessions_path(@workspace)

    assert_response :success
    assert_select "textarea#text", count: 1
    assert_select "input[type='file']", count: 1
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

  test "inline_update preserves parser incomplete note block" do
    note = "자동 반영 제외 1건\n1. 누락: 날짜 - 네이버페이 / 12,000원"
    @parsing_session.update!(
      source_type: "file_upload",
      notes: "이전 메모\n\n#{ParsingSession.incomplete_parse_note_block(note)}"
    )

    patch inline_update_workspace_parsing_session_path(@workspace, @parsing_session),
          params: { field: "notes", value: "새 사용자 메모" },
          as: :turbo_stream

    assert_response :success
    @parsing_session.reload
    assert_equal "새 사용자 메모", @parsing_session.user_visible_notes
    assert_equal note, @parsing_session.incomplete_parse_note_text
    assert_includes @parsing_session.notes, ParsingSession::INCOMPLETE_PARSE_NOTE_START_MARKER
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
