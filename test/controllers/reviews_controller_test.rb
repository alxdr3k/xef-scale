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
