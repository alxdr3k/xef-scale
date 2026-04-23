require "test_helper"

# End-to-end coverage for the highest-leverage user path: a parsing session is
# created with a mix of pending transactions + a duplicate-of-an-existing-row,
# the user excludes one row, decides "keep_original" on the duplicate, then
# either commits or rolls back the import. The model + controller layers each
# have unit tests; this file is the safety net that proves they wire together.
class ParsingReviewFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:admin)
    @workspace = workspaces(:main_workspace)
    sign_in @user

    @session = @workspace.parsing_sessions.create!(
      source_type: "text_paste",
      status: "completed",
      review_status: "pending_review",
      total_count: 3,
      success_count: 3,
      duplicate_count: 1,
      started_at: 2.minutes.ago,
      completed_at: 1.minute.ago
    )

    @keep = @workspace.transactions.create!(
      date: Date.current, amount: 1_000, merchant: "유지될 거래",
      status: "pending_review", parsing_session: @session
    )
    @drop = @workspace.transactions.create!(
      date: Date.current, amount: 2_000, merchant: "사용자가 제외할 거래",
      status: "pending_review", parsing_session: @session
    )
    @original = @workspace.transactions.create!(
      date: Date.current, amount: 4_500, merchant: "원본 가맹점", status: "committed"
    )
    @duplicate_new = @workspace.transactions.create!(
      date: Date.current, amount: 4_500, merchant: "원본 가맹점",
      status: "pending_review", parsing_session: @session
    )
    @confirmation = @session.duplicate_confirmations.create!(
      original_transaction: @original, new_transaction: @duplicate_new,
      status: "pending"
    )
  end

  test "exclude → resolve duplicate → commit lands the right rows on the ledger" do
    # Block commit while the duplicate is unresolved.
    post commit_workspace_parsing_session_path(@workspace, @session)
    assert_match(/중복/, flash[:alert])
    assert @session.reload.review_pending?

    # Exclude one pending row from the import.
    post bulk_update_workspace_parsing_session_path(@workspace, @session),
         params: { transaction_ids: @drop.id.to_s, bulk_action: "delete" }
    assert @drop.reload.rolled_back?, "excluded row should be rolled_back, not soft-deleted"

    # Decide the duplicate as keep_original.
    patch workspace_parsing_session_duplicate_confirmation_path(@workspace, @session, @confirmation),
          params: { decision: "keep_original" }
    assert_equal "keep_original", @confirmation.reload.status

    # Now commit succeeds.
    post commit_workspace_parsing_session_path(@workspace, @session)
    assert @session.reload.review_committed?

    @keep.reload
    @drop.reload
    @original.reload
    @duplicate_new.reload

    assert @keep.committed?, "kept row should be committed"
    assert @drop.rolled_back?, "excluded row stays excluded"
    assert @original.committed?, "existing original is untouched"
    assert_not @original.deleted, "keep_original must not soft-delete the original"
    assert @duplicate_new.rolled_back?, "duplicate decided keep_original is dropped from commit set"
  end

  test "rollback restores any originals that were soft-deleted by keep_new" do
    # Resolve duplicate as keep_new, commit, then roll back.
    patch workspace_parsing_session_duplicate_confirmation_path(@workspace, @session, @confirmation),
          params: { decision: "keep_new" }
    post commit_workspace_parsing_session_path(@workspace, @session)
    assert @session.reload.review_committed?
    assert @original.reload.deleted, "keep_new should soft-delete the original at commit time"

    post rollback_workspace_parsing_session_path(@workspace, @session)
    assert @session.reload.review_rolled_back?

    @original.reload
    @duplicate_new.reload
    @keep.reload

    assert_not @original.deleted, "rollback must restore the soft-deleted original"
    assert @duplicate_new.rolled_back?
    assert @keep.rolled_back?
  end

  test "discard throws away pending rows without touching existing originals" do
    post discard_workspace_parsing_session_path(@workspace, @session)
    assert @session.reload.review_discarded?

    @original.reload
    assert_not @original.deleted, "discard must not touch existing committed data"
    assert_not Transaction.exists?(@keep.id), "pending rows are destroyed by discard"
    assert_not Transaction.exists?(@duplicate_new.id)
  end
end
