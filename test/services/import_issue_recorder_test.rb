require "test_helper"

class ImportIssueRecorderTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:main_workspace)
    @processed_file = @workspace.processed_files.create!(
      filename: "statement.png",
      original_filename: "statement.png",
      status: "completed"
    )
    @file_session = @workspace.parsing_sessions.create!(
      source_type: "file_upload",
      status: "completed",
      review_status: "pending_review",
      processed_file: @processed_file
    )
    @text_session = @workspace.parsing_sessions.create!(
      source_type: "text_paste",
      status: "completed",
      review_status: "pending_review"
    )
  end

  test "split_and_record diverts incomplete rows and returns the complete subset" do
    complete = { date: Date.current, merchant: "스타벅스", amount: 5_000 }
    no_merchant = { date: Date.current, merchant: "", amount: 3_000 }
    no_amount = { date: Date.current, merchant: "맥도날드", amount: 0 }
    no_date = { date: nil, merchant: "투썸", amount: 4_500 }

    recorder = ImportIssueRecorder.new(
      parsing_session: @file_session,
      source_type: "image_upload",
      processed_file: @processed_file
    )

    remaining, recorded, failed = recorder.split_and_record([ complete, no_merchant, no_amount, no_date ])

    assert_equal [ complete ], remaining
    assert_equal 3, recorded
    assert_equal 0, failed
    assert_equal 3, @file_session.import_issues.count

    types = @file_session.import_issues.pluck(:issue_type).uniq
    assert_equal [ "missing_required_fields" ], types
  end

  test "complete rows alone produce no issues" do
    rows = [
      { date: Date.current, merchant: "A", amount: 100 },
      { date: Date.current, merchant: "B", amount: 200 }
    ]

    recorder = ImportIssueRecorder.new(
      parsing_session: @file_session,
      source_type: "image_upload",
      processed_file: @processed_file
    )

    remaining, recorded, failed = recorder.split_and_record(rows)

    assert_equal rows, remaining
    assert_equal 0, recorded
    assert_equal 0, failed
    assert_equal 0, @file_session.import_issues.count
  end

  test "text_paste source records issues without processed_file" do
    rows = [ { date: Date.current, merchant: "", amount: 5_000 } ]

    recorder = ImportIssueRecorder.new(
      parsing_session: @text_session,
      source_type: "text_paste"
    )

    remaining, recorded, failed = recorder.split_and_record(rows)

    assert_empty remaining
    assert_equal 1, recorded
    assert_equal 0, failed

    issue = @text_session.import_issues.first
    assert_equal "text_paste", issue.source_type
    assert_nil issue.processed_file_id
    assert_includes issue.missing_fields, "merchant"
  end

  test "persistence failure logs and is counted as failed" do
    output = StringIO.new
    original_logger = Rails.logger
    Rails.logger = Logger.new(output)

    # Force a validation failure by passing a session from another workspace.
    other_session = workspaces(:other_workspace).parsing_sessions.create!(
      source_type: "file_upload",
      status: "completed",
      review_status: "pending_review"
    )
    recorder = ImportIssueRecorder.new(
      parsing_session: other_session,
      source_type: "image_upload",
      processed_file: @processed_file
    )

    remaining, recorded, failed = recorder.split_and_record([ { date: nil, merchant: "x", amount: 100 } ])

    assert_empty remaining
    assert_equal 0, recorded
    assert_equal 1, failed
    assert_includes output.string, "[ImportIssueRecorder]"
    assert_equal 0, other_session.import_issues.count
  ensure
    Rails.logger = original_logger
  end

  test "missing_fields captures only the fields that are actually missing" do
    row = { date: Date.current, merchant: "스타벅스", amount: 0 }

    recorder = ImportIssueRecorder.new(
      parsing_session: @file_session,
      source_type: "image_upload",
      processed_file: @processed_file
    )

    recorder.split_and_record([ row ])

    issue = @file_session.import_issues.first
    assert_equal [ "amount" ], issue.missing_fields
  end
end
