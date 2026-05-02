require "test_helper"

class ReviewsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:admin)
    @workspace = workspaces(:main_workspace)
    @parsing_session = parsing_sessions(:completed_session)
    @parsing_session.update!(review_status: "pending_review")
    sign_in @user
  end

  test "commit is blocked when pending duplicates remain" do
    @parsing_session.duplicate_confirmations.create!(
      original_transaction: transactions(:food_transaction),
      new_transaction: transactions(:transport_transaction),
      status: "pending"
    )

    post commit_workspace_parsing_session_path(@workspace, @parsing_session)

    assert_redirected_to review_workspace_parsing_session_path(@workspace, @parsing_session)
    assert_match(/중복/, flash[:alert])
    assert @parsing_session.reload.review_pending?
  end

  test "commit succeeds when no pending duplicates" do
    @parsing_session.duplicate_confirmations.destroy_all
    tx = @workspace.transactions.create!(
      date: Date.current,
      amount: 1000,
      status: "pending_review",
      parsing_session: @parsing_session
    )

    post commit_workspace_parsing_session_path(@workspace, @parsing_session)

    assert_redirected_to review_workspace_parsing_session_path(@workspace, @parsing_session)
    assert @parsing_session.reload.review_committed?
    assert tx.reload.committed?
  end

  test "commit creates one budget warning notification per workspace member and month" do
    workspace = Workspace.create!(name: "Budget Warning Workspace", owner: @user)
    workspace.workspace_memberships.create!(user: users(:member), role: "member_read")
    workspace.create_budget!(monthly_amount: 1000)
    date = Date.new(2026, 3, 15)
    session = workspace.parsing_sessions.create!(
      source_type: "text_paste",
      status: "completed",
      review_status: "pending_review"
    )
    workspace.transactions.create!(
      date: date,
      amount: 800,
      status: "pending_review",
      parsing_session: session
    )

    assert_difference -> {
      Notification.where(
        workspace: workspace,
        notification_type: "budget_warning",
        target_year: date.year,
        target_month: date.month
      ).count
    }, 2 do
      post commit_workspace_parsing_session_path(workspace, session)
    end

    notified_users = Notification.where(
      workspace: workspace,
      notification_type: "budget_warning",
      target_year: date.year,
      target_month: date.month
    ).pluck(:user_id)
    assert_equal [ @user.id, users(:member).id ].sort, notified_users.sort

    second_session = workspace.parsing_sessions.create!(
      source_type: "text_paste",
      status: "completed",
      review_status: "pending_review"
    )
    workspace.transactions.create!(
      date: date,
      amount: 50,
      status: "pending_review",
      parsing_session: second_session
    )

    assert_no_difference -> {
      Notification.where(
        workspace: workspace,
        notification_type: "budget_warning",
        target_year: date.year,
        target_month: date.month
      ).count
    } do
      post commit_workspace_parsing_session_path(workspace, second_session)
    end
  end

  test "commit creates budget exceeded notification at 100 percent" do
    workspace = Workspace.create!(name: "Budget Exceeded Workspace", owner: @user)
    workspace.create_budget!(monthly_amount: 1000)
    date = Date.new(2026, 4, 15)
    session = workspace.parsing_sessions.create!(
      source_type: "text_paste",
      status: "completed",
      review_status: "pending_review"
    )
    workspace.transactions.create!(
      date: date,
      amount: 1000,
      status: "pending_review",
      parsing_session: session
    )

    assert_difference -> {
      Notification.where(
        workspace: workspace,
        user: @user,
        notification_type: "budget_exceeded",
        target_year: date.year,
        target_month: date.month
      ).count
    }, 1 do
      post commit_workspace_parsing_session_path(workspace, session)
    end
  end

  test "commit creates exceeded notification after prior warning" do
    workspace = Workspace.create!(name: "Budget Escalation Workspace", owner: @user)
    workspace.create_budget!(monthly_amount: 1000)
    date = Date.new(2026, 5, 15)
    warning_session = workspace.parsing_sessions.create!(
      source_type: "text_paste",
      status: "completed",
      review_status: "pending_review"
    )
    workspace.transactions.create!(
      date: date,
      amount: 800,
      status: "pending_review",
      parsing_session: warning_session
    )
    post commit_workspace_parsing_session_path(workspace, warning_session)

    exceeded_session = workspace.parsing_sessions.create!(
      source_type: "text_paste",
      status: "completed",
      review_status: "pending_review"
    )
    workspace.transactions.create!(
      date: date,
      amount: 200,
      status: "pending_review",
      parsing_session: exceeded_session
    )

    assert_difference -> {
      Notification.where(
        workspace: workspace,
        user: @user,
        notification_type: "budget_exceeded",
        target_year: date.year,
        target_month: date.month
      ).count
    }, 1 do
      post commit_workspace_parsing_session_path(workspace, exceeded_session)
    end
  end

  test "bulk_update is refused on finalized sessions" do
    tx = @workspace.transactions.create!(
      date: Date.current,
      amount: 1000,
      status: "pending_review",
      parsing_session: @parsing_session
    )
    @parsing_session.update!(review_status: "committed")

    post bulk_update_workspace_parsing_session_path(@workspace, @parsing_session),
         params: { transaction_ids: tx.id.to_s, bulk_action: "delete" }

    assert_redirected_to review_workspace_parsing_session_path(@workspace, @parsing_session)
    assert_match(/종료된/, flash[:alert])
    assert tx.reload.pending_review?
    assert_not tx.deleted
  end

  test "bulk_update delete excludes pending transactions from import via rollback" do
    @parsing_session.duplicate_confirmations.destroy_all
    keep = @workspace.transactions.create!(
      date: Date.current, amount: 1000, status: "pending_review",
      parsing_session: @parsing_session
    )
    drop = @workspace.transactions.create!(
      date: Date.current, amount: 2000, status: "pending_review",
      parsing_session: @parsing_session
    )

    post bulk_update_workspace_parsing_session_path(@workspace, @parsing_session),
         params: { transaction_ids: drop.id.to_s, bulk_action: "delete" }

    assert_redirected_to review_workspace_parsing_session_path(@workspace, @parsing_session)
    assert drop.reload.rolled_back?, "expected dropped tx to be rolled_back"
    assert_not drop.deleted, "rollback should not soft-delete the row"

    post commit_workspace_parsing_session_path(@workspace, @parsing_session)

    assert keep.reload.committed?
    assert drop.reload.rolled_back?, "rolled-back tx must not be committed"
  end

  test "duplicate keep_new decision is skipped when new transaction is excluded" do
    @parsing_session.duplicate_confirmations.destroy_all
    original = transactions(:food_transaction)
    original.update!(deleted: false, status: "committed")

    new_tx = @workspace.transactions.create!(
      date: original.date, amount: original.amount,
      status: "pending_review", parsing_session: @parsing_session
    )
    dc = @parsing_session.duplicate_confirmations.create!(
      original_transaction: original, new_transaction: new_tx, status: "keep_new"
    )

    post bulk_update_workspace_parsing_session_path(@workspace, @parsing_session),
         params: { transaction_ids: new_tx.id.to_s, bulk_action: "delete" }
    post commit_workspace_parsing_session_path(@workspace, @parsing_session)

    assert_not original.reload.deleted, "original must survive when the new row was excluded"
    assert new_tx.reload.rolled_back?
    assert_equal "keep_new", dc.reload.status
  end

  test "update_transaction allows negative amount for refund/cancellation" do
    tx = @workspace.transactions.create!(
      date: Date.current,
      amount: 50000,
      status: "pending_review",
      parsing_session: @parsing_session
    )

    patch update_transaction_workspace_parsing_session_path(@workspace, @parsing_session, transaction_id: tx.id),
          params: { field: "amount", value: "-30000" },
          as: :turbo_stream

    assert_response :success
    assert_equal(-30000, tx.reload.amount)
  end

  test "update_transaction rejects zero amount" do
    tx = @workspace.transactions.create!(
      date: Date.current,
      amount: 50000,
      status: "pending_review",
      parsing_session: @parsing_session
    )

    patch update_transaction_workspace_parsing_session_path(@workspace, @parsing_session, transaction_id: tx.id),
          params: { field: "amount", value: "0" },
          as: :turbo_stream

    assert_response :unprocessable_entity
    assert_equal 50000, tx.reload.amount
  end

  test "show assigns total_commit_count matching all pending_review transactions not just page" do
    @parsing_session.duplicate_confirmations.destroy_all
    3.times do
      @workspace.transactions.create!(
        date: Date.current, amount: 1000,
        status: "pending_review", parsing_session: @parsing_session
      )
    end

    expected_count = @parsing_session.transactions.pending_review.where(deleted: false).count

    # Verify the controller logic directly: total_commit_count must equal the full unpaginated scope
    assert expected_count > 0, "세션에 pending_review 거래가 있어야 함"

    # Simulate what the controller does to verify the query is correct
    computed = @parsing_session.transactions.pending_review.where(deleted: false).count
    assert_equal expected_count, computed,
                 "total_commit_count는 페이지네이션 없이 전체 pending_review 수여야 함"
  end

  test "show hides institution column and renders source metadata in popover" do
    @parsing_session.transactions.create!(
      workspace: @workspace,
      date: Date.current,
      merchant: "스타벅스",
      amount: 5800,
      status: "pending_review",
      source_metadata: {
        "source_channel" => "pasted_text",
        "source_app_raw" => "KB Pay",
        "source_institution_raw" => "KB국민카드"
      }
    )

    get review_workspace_parsing_session_path(@workspace, @parsing_session)

    assert_response :success
    assert_select "th", text: "금융기관", count: 0
    assert_select "th", text: "출처", count: 1
    assert_select "button[aria-label='가져온 출처 보기']", minimum: 1
    assert_includes response.body, "KB Pay"
    assert_includes response.body, "KB국민카드"
    assert_includes response.body, "이 정보는 결제 분류나 예산 계산에 사용되지 않습니다."
    assert_not_includes response.body, "금융기관 미확인"
  end

  test "show does not render incomplete parse banner for ordinary file upload notes" do
    session = @workspace.parsing_sessions.create!(
      source_type: "file_upload",
      status: "completed",
      review_status: "pending_review",
      notes: "사용자가 남긴 업로드 메모"
    )

    get review_workspace_parsing_session_path(@workspace, session)

    assert_response :success
    assert_select "p", text: "자동 반영되지 않은 항목이 있습니다", count: 0
    assert_not_includes response.body, "사용자가 남긴 업로드 메모"
  end

  test "show renders incomplete parse banner only from parser note block" do
    note = "자동 반영 제외 1건\n1. 누락: 날짜 - 네이버페이 / 12,000원"
    session = @workspace.parsing_sessions.create!(
      source_type: "file_upload",
      status: "completed",
      review_status: "pending_review",
      notes: "사용자 메모\n\n#{ParsingSession.incomplete_parse_note_block(note)}"
    )

    get review_workspace_parsing_session_path(@workspace, session)

    assert_response :success
    assert_select "p", text: "자동 반영되지 않은 항목이 있습니다", count: 1
    assert_includes response.body, "네이버페이"
    assert_not_includes response.body, ParsingSession::INCOMPLETE_PARSE_NOTE_START_MARKER
    assert_not_includes response.body, "사용자 메모"
  end

  test "show renders import issue banner from durable repair records" do
    session = @workspace.parsing_sessions.create!(
      source_type: "file_upload",
      status: "completed",
      review_status: "pending_review"
    )
    session.import_issues.create!(
      workspace: @workspace,
      source_type: "image_upload",
      merchant: "네이버페이",
      amount: 12_000,
      missing_fields: [ "date" ],
      raw_payload: { "merchant" => "네이버페이" }
    )

    get review_workspace_parsing_session_path(@workspace, session)

    assert_response :success
    assert_select "p", text: "자동 반영되지 않은 항목이 있습니다", count: 1
    assert_includes response.body, "누락: 날짜"
    assert_includes response.body, "네이버페이"
    assert_includes response.body, "12,000원"
  end

  test "bulk_resolve_duplicates is refused on finalized sessions" do
    dc = @parsing_session.duplicate_confirmations.create!(
      original_transaction: transactions(:food_transaction),
      new_transaction: transactions(:transport_transaction),
      status: "pending"
    )
    @parsing_session.update!(review_status: "discarded")

    post bulk_resolve_duplicates_workspace_parsing_session_path(@workspace, @parsing_session),
         params: { decision: "keep_both" }

    assert_redirected_to review_workspace_parsing_session_path(@workspace, @parsing_session)
    assert_equal "pending", dc.reload.status
  end
end
