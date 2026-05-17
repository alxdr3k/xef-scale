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
    event = @workspace.import_review_events.create!(
      parsing_session: @session,
      event_type: "transaction_updated",
      changed_fields: [ "category_id", :category_id, "merchant", "" ]
    )

    assert_equal [ "category_id", "merchant" ], event.changed_fields
  end

  test "session_terminations scope" do
    @workspace.import_review_events.create!(
      parsing_session: @session,
      event_type: "session_committed",
      changed_fields: []
    )
    @workspace.import_review_events.create!(
      parsing_session: @session,
      event_type: "transaction_updated",
      changed_fields: [ "merchant" ]
    )

    assert_equal 1, @workspace.import_review_events.session_terminations.count
    assert_equal 1, @workspace.import_review_events.transaction_updates.count
  end
end
