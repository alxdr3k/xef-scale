require "test_helper"

class ImportReviewEventRecorderTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:main_workspace)
    @session = @workspace.parsing_sessions.create!(
      source_type: "file_upload",
      status: "completed",
      review_status: "pending_review"
    )
  end

  test "records a session event without transaction" do
    event = ImportReviewEventRecorder.record(
      workspace: @workspace,
      parsing_session: @session,
      event_type: "session_committed"
    )

    assert event.persisted?
    assert_equal "session_committed", event.event_type
    assert_nil event.reviewed_transaction_id
    assert_equal [], event.changed_fields
  end

  test "records a transaction_updated event with changed fields" do
    transaction = @workspace.transactions.create!(
      date: Date.current,
      amount: 1_000
    )

    event = ImportReviewEventRecorder.record(
      workspace: @workspace,
      parsing_session: @session,
      reviewed_transaction: transaction,
      event_type: "transaction_updated",
      changed_fields: [ "category_id", "merchant" ]
    )

    assert event.persisted?
    assert_equal transaction.id, event.reviewed_transaction_id
    assert_equal [ "category_id", "merchant" ], event.changed_fields
  end

  test "returns nil and logs on persistence failure" do
    output = StringIO.new
    original_logger = Rails.logger
    Rails.logger = Logger.new(output)

    result = ImportReviewEventRecorder.record(
      workspace: @workspace,
      parsing_session: @session,
      event_type: "not_a_real_event"
    )

    assert_nil result
    assert_includes output.string, "[ImportReviewEvent]"
  ensure
    Rails.logger = original_logger
  end
end
