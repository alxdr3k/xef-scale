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
end
