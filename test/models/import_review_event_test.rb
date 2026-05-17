require "test_helper"

class ImportReviewEventTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:main_workspace)
    @session = @workspace.parsing_sessions.create!(
      source_type: "file_upload",
      status: "completed",
      review_status: "pending_review"
    )
  end

  test "valid event without reviewed transaction" do
    event = @workspace.import_review_events.build(
      parsing_session: @session,
      event_type: "session_committed",
      changed_fields: []
    )

    assert event.valid?
    assert_nil event.reviewed_transaction_id
  end

  test "rejects unknown event type" do
    event = @workspace.import_review_events.build(
      parsing_session: @session,
      event_type: "not_a_real_event",
      changed_fields: []
    )

    assert_not event.valid?
    assert_includes event.errors[:event_type].join, "included"
  end

  test "normalizes changed fields" do
    tx = @workspace.transactions.create!(date: Date.current, amount: 1_000, parsing_session: @session)
    event = @workspace.import_review_events.create!(
      parsing_session: @session,
      reviewed_transaction: tx,
      event_type: "transaction_updated",
      changed_fields: [ "category_id", :category_id, "merchant", "" ]
    )

    assert_equal [ "category_id", "merchant" ], event.changed_fields
  end

  test "session_terminations scope" do
    tx = @workspace.transactions.create!(date: Date.current, amount: 1_000, parsing_session: @session)
    @workspace.import_review_events.create!(
      parsing_session: @session,
      event_type: "session_committed",
      changed_fields: []
    )
    @workspace.import_review_events.create!(
      parsing_session: @session,
      reviewed_transaction: tx,
      event_type: "transaction_updated",
      changed_fields: [ "merchant" ]
    )

    assert_equal 1, @workspace.import_review_events.session_terminations.count
    assert_equal 1, @workspace.import_review_events.transaction_updates.count
  end

  test "transaction_updated requires reviewed transaction" do
    event = @workspace.import_review_events.build(
      parsing_session: @session,
      event_type: "transaction_updated",
      changed_fields: [ "merchant" ]
    )

    assert_not event.valid?
    assert_includes event.errors[:reviewed_transaction].join, "must be present"
  end

  test "transaction_updated requires at least one changed field" do
    tx = @workspace.transactions.create!(date: Date.current, amount: 1_000, parsing_session: @session)
    event = @workspace.import_review_events.build(
      parsing_session: @session,
      reviewed_transaction: tx,
      event_type: "transaction_updated",
      changed_fields: []
    )

    assert_not event.valid?
    assert_includes event.errors[:changed_fields].join, "at least one field"
  end

  test "transaction_excluded requires reviewed transaction" do
    event = @workspace.import_review_events.build(
      parsing_session: @session,
      event_type: "transaction_excluded",
      changed_fields: []
    )

    assert_not event.valid?
    assert_includes event.errors[:reviewed_transaction].join, "must be present"
  end

  test "session termination rejects reviewed transaction" do
    tx = @workspace.transactions.create!(date: Date.current, amount: 1_000, parsing_session: @session)
    event = @workspace.import_review_events.build(
      parsing_session: @session,
      reviewed_transaction: tx,
      event_type: "session_committed",
      changed_fields: []
    )

    assert_not event.valid?
    assert_includes event.errors[:reviewed_transaction].join, "must be blank"
  end

  test "session termination rejects changed fields" do
    event = @workspace.import_review_events.build(
      parsing_session: @session,
      event_type: "session_committed",
      changed_fields: [ "merchant" ]
    )

    assert_not event.valid?
    assert_includes event.errors[:changed_fields].join, "must be empty"
  end

  test "parsing session must belong to same workspace" do
    other_session = workspaces(:other_workspace).parsing_sessions.create!(
      source_type: "file_upload",
      status: "completed",
      review_status: "pending_review"
    )
    event = @workspace.import_review_events.build(
      parsing_session: other_session,
      event_type: "session_committed",
      changed_fields: []
    )

    assert_not event.valid?
    assert_includes event.errors[:parsing_session_id].join, "same workspace"
  end

  test "reviewed transaction must belong to same workspace" do
    other_tx = workspaces(:other_workspace).transactions.create!(date: Date.current, amount: 1_000)
    event = @workspace.import_review_events.build(
      parsing_session: @session,
      reviewed_transaction: other_tx,
      event_type: "transaction_updated",
      changed_fields: [ "merchant" ]
    )

    assert_not event.valid?
    assert_includes event.errors[:reviewed_transaction_id].join, "same workspace"
  end

  test "reviewed transaction must belong to the parsing session" do
    other_session = @workspace.parsing_sessions.create!(
      source_type: "text_paste",
      status: "completed",
      review_status: "pending_review"
    )
    tx = @workspace.transactions.create!(date: Date.current, amount: 1_000, parsing_session: other_session)
    event = @workspace.import_review_events.build(
      parsing_session: @session,
      reviewed_transaction: tx,
      event_type: "transaction_updated",
      changed_fields: [ "merchant" ]
    )

    assert_not event.valid?
    assert_includes event.errors[:reviewed_transaction_id].join, "parsing session"
  end
end
