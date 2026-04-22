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
    assert_not tx.reload.deleted
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
