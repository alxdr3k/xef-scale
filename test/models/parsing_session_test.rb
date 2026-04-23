require "test_helper"

class ParsingSessionTest < ActiveSupport::TestCase
  test "parsing session is valid with valid attributes" do
    session = parsing_sessions(:completed_session)
    assert session.valid?
  end

  test "parsing session requires valid status" do
    session = ParsingSession.new(
      processed_file: processed_files(:completed_file),
      status: "invalid"
    )
    assert_not session.valid?
    assert_includes session.errors[:status], "is not included in the list"
  end

  test "pending? returns true for pending status" do
    session = parsing_sessions(:pending_session)
    assert session.pending?
  end

  test "processing? returns true for processing status" do
    session = parsing_sessions(:processing_session)
    assert session.processing?
  end

  test "completed? returns true for completed status" do
    session = parsing_sessions(:completed_session)
    assert session.completed?
  end

  test "start! updates status and started_at" do
    session = parsing_sessions(:pending_session)
    session.start!

    assert session.processing?
    assert_not_nil session.started_at
  end

  test "complete! updates status and stats" do
    session = parsing_sessions(:processing_session)
    stats = { total: 10, success: 8, duplicate: 1, error: 1 }
    session.complete!(stats)

    assert session.completed?
    assert_not_nil session.completed_at
    assert_equal 10, session.total_count
    assert_equal 8, session.success_count
    assert_equal 1, session.duplicate_count
    assert_equal 1, session.error_count
  end

  test "fail! updates status to failed" do
    session = parsing_sessions(:processing_session)
    session.fail!

    assert session.failed?
    assert_not_nil session.completed_at
  end

  test "duration returns time difference" do
    session = parsing_sessions(:completed_session)
    assert_not_nil session.duration
    assert session.duration > 0
  end

  test "duration returns nil when incomplete" do
    session = parsing_sessions(:pending_session)
    assert_nil session.duration
  end

  test "has_duplicates? returns true when duplicate_count > 0" do
    session = parsing_sessions(:completed_session)
    assert session.has_duplicates?
  end

  test "has_duplicates? returns false when duplicate_count is 0" do
    session = parsing_sessions(:pending_session)
    assert_not session.has_duplicates?
  end

  test "pending_duplicates returns pending duplicate confirmations" do
    session = parsing_sessions(:completed_session)
    pending = session.pending_duplicates
    pending.each do |dc|
      assert dc.pending?
    end
  end

  test "recent scope orders by created_at desc" do
    sessions = ParsingSession.recent
    sessions.each_cons(2) do |a, b|
      assert a.created_at >= b.created_at
    end
  end

  test "completed scope returns only completed sessions" do
    sessions = ParsingSession.completed
    sessions.each do |s|
      assert s.completed?
    end
  end

  test "failed? returns true for failed status" do
    session = ParsingSession.new(status: "failed")
    assert session.failed?
  end

  test "has_duplicates? handles nil duplicate_count" do
    session = ParsingSession.new(status: "pending", duplicate_count: nil)
    assert_not session.has_duplicates?
  end

  test "complete! with default stats" do
    session = parsing_sessions(:processing_session)
    session.complete!

    assert session.completed?
    assert_equal 0, session.total_count
    assert_equal 0, session.success_count
  end

  test "duration returns nil when started_at is nil" do
    session = ParsingSession.new(status: "pending", started_at: nil, completed_at: Time.current)
    assert_nil session.duration
  end

  test "duration returns nil when completed_at is nil" do
    session = ParsingSession.new(status: "processing", started_at: Time.current, completed_at: nil)
    assert_nil session.duration
  end

  test "has_unresolved_duplicates? returns true when pending duplicates exist" do
    session = parsing_sessions(:completed_session)
    session.duplicate_confirmations.create!(
      original_transaction: transactions(:food_transaction),
      new_transaction: transactions(:transport_transaction),
      status: "pending"
    )
    assert session.has_unresolved_duplicates?
  end

  test "has_unresolved_duplicates? returns false when no pending duplicates" do
    session = parsing_sessions(:completed_session)
    session.duplicate_confirmations.destroy_all
    assert_not session.has_unresolved_duplicates?
  end

  test "can_commit? returns false when unresolved duplicates exist" do
    session = parsing_sessions(:completed_session)
    session.update!(review_status: "pending_review")
    session.duplicate_confirmations.create!(
      original_transaction: transactions(:food_transaction),
      new_transaction: transactions(:transport_transaction),
      status: "pending"
    )
    assert_not session.can_commit?
  end

  test "can_commit? returns true when duplicates are all resolved" do
    session = parsing_sessions(:completed_session)
    session.update!(review_status: "pending_review")
    session.duplicate_confirmations.destroy_all
    assert session.can_commit?
  end

  test "commit_all! is blocked while duplicates remain unresolved" do
    session = parsing_sessions(:completed_session)
    session.update!(review_status: "pending_review")
    session.duplicate_confirmations.create!(
      original_transaction: transactions(:food_transaction),
      new_transaction: transactions(:transport_transaction),
      status: "pending"
    )
    assert_not session.commit_all!(users(:admin))
    assert session.review_pending?
  end

  # --- Deferred duplicate-decision application ---

  # A fresh session + original + new pending_review transaction with a resolved
  # DuplicateConfirmation between them. Lets us exercise commit/discard/rollback
  # without polluting the shared completed_session fixture.
  def build_session_with_duplicate(decision:)
    workspace = workspaces(:main_workspace)
    session = workspace.parsing_sessions.create!(
      source_type: "text_paste",
      status: "completed",
      review_status: "pending_review",
      total_count: 1,
      success_count: 1,
      duplicate_count: 1,
      started_at: 2.minutes.ago,
      completed_at: 1.minute.ago
    )
    original = workspace.transactions.create!(
      date: Date.new(2026, 1, 5),
      merchant: "스타벅스강남점",
      amount: 5800,
      status: "committed"
    )
    new_tx = workspace.transactions.create!(
      date: Date.new(2026, 1, 5),
      merchant: "스타벅스강남점",
      amount: 5800,
      status: "pending_review",
      parsing_session: session
    )
    session.duplicate_confirmations.create!(
      original_transaction: original,
      new_transaction: new_tx,
      status: decision
    )
    [ session, original, new_tx ]
  end

  test "discard_all! with keep_new decision leaves original committed transaction untouched" do
    session, original, new_tx = build_session_with_duplicate(decision: "keep_new")

    assert session.discard_all!

    # Pending new transaction was destroyed
    assert_not Transaction.exists?(new_tx.id)
    # Original stays active — no silent data loss on discard
    original.reload
    assert_not original.deleted
    assert original.committed?
  end

  test "commit_all! with keep_new soft-deletes original and commits new" do
    session, original, new_tx = build_session_with_duplicate(decision: "keep_new")

    assert session.commit_all!(users(:admin))

    original.reload
    new_tx.reload

    assert original.deleted, "original should be soft-deleted after keep_new commit"
    assert original.committed?, "original status is unchanged"
    assert_not new_tx.deleted
    assert new_tx.committed?
  end

  test "rollback_all! after keep_new commit restores the original" do
    session, original, new_tx = build_session_with_duplicate(decision: "keep_new")

    assert session.commit_all!(users(:admin))
    assert session.rollback_all!(users(:admin))

    original.reload
    new_tx.reload

    assert_not original.deleted, "original should be restored on rollback"
    assert original.committed?
    assert new_tx.rolled_back?
  end

  test "commit_all! with keep_original leaves original untouched and does not commit the new pending transaction" do
    session, original, new_tx = build_session_with_duplicate(decision: "keep_original")

    assert session.commit_all!(users(:admin))

    original.reload
    new_tx.reload

    assert_not original.deleted
    assert original.committed?
    # The new pending transaction must not end up committed — otherwise a
    # "deleted + committed" or duplicate-committed row would leak through.
    assert new_tx.rolled_back?
    assert_not new_tx.committed?
  end

  test "commit_all! with keep_both commits new transaction and keeps original" do
    session, original, new_tx = build_session_with_duplicate(decision: "keep_both")

    assert session.commit_all!(users(:admin))

    original.reload
    new_tx.reload

    assert_not original.deleted
    assert original.committed?
    assert new_tx.committed?
    assert_not new_tx.deleted
  end

  test "commit_summary reports counts the user can verify after commit" do
    workspace = workspaces(:main_workspace)
    session = workspace.parsing_sessions.create!(
      source_type: "text_paste", status: "completed", review_status: "pending_review",
      total_count: 4, success_count: 4
    )
    keep = workspace.transactions.create!(
      date: Date.current, amount: 1000, status: "pending_review", parsing_session: session
    )
    workspace.transactions.create!(
      date: Date.current, amount: 2000, status: "pending_review", parsing_session: session,
      category: categories(:food)
    )
    excluded = workspace.transactions.create!(
      date: Date.current, amount: 3000, status: "pending_review", parsing_session: session
    )
    excluded.rollback!

    original = workspace.transactions.create!(
      date: Date.current, amount: 4000, status: "committed"
    )
    new_dup = workspace.transactions.create!(
      date: Date.current, amount: 4000, status: "pending_review", parsing_session: session
    )
    session.duplicate_confirmations.create!(
      original_transaction: original, new_transaction: new_dup, status: "keep_original"
    )

    assert session.commit_all!(users(:admin))

    summary = session.commit_summary
    assert_equal 2, summary[:committed], "keep + categorized commit; new_dup is rolled_back, excluded too"
    assert_equal 2, summary[:excluded]
    assert_equal 1, summary[:uncategorized], "keep tx has no category"
    assert_equal 1, summary[:originals_kept]
    assert_equal 0, summary[:originals_replaced]
  end
end
