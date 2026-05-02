require "test_helper"

class ImportIssueTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:main_workspace)
    @session = @workspace.parsing_sessions.create!(
      source_type: "file_upload",
      status: "completed",
      review_status: "pending_review"
    )
  end

  test "is valid with supported missing fields" do
    issue = @workspace.import_issues.build(
      parsing_session: @session,
      source_type: "image_upload",
      missing_fields: [ "date", "merchant" ],
      raw_payload: { "merchant" => "네이버페이" }
    )

    assert issue.valid?
  end

  test "normalizes missing fields" do
    issue = @workspace.import_issues.create!(
      parsing_session: @session,
      source_type: "image_upload",
      missing_fields: [ "date", :date, "merchant", "" ]
    )

    assert_equal [ "date", "merchant" ], issue.missing_fields
  end

  test "requires at least one missing field" do
    issue = @workspace.import_issues.build(
      parsing_session: @session,
      source_type: "image_upload",
      missing_fields: []
    )

    assert_not issue.valid?
    assert_includes issue.errors[:missing_fields].join, "at least one"
  end

  test "ambiguous duplicate is valid without missing fields when duplicate transaction is present" do
    duplicate = @workspace.transactions.create!(
      date: Date.current,
      merchant: "스타벅스강남점",
      amount: 5_000,
      status: "committed"
    )
    issue = @workspace.import_issues.build(
      parsing_session: @session,
      duplicate_transaction: duplicate,
      source_type: "image_upload",
      issue_type: "ambiguous_duplicate",
      date: Date.current,
      merchant: "스타벅스 강남",
      amount: 5_000,
      missing_fields: []
    )

    assert issue.valid?
  end

  test "ambiguous duplicate requires duplicate transaction" do
    issue = @workspace.import_issues.build(
      parsing_session: @session,
      source_type: "text_paste",
      issue_type: "ambiguous_duplicate",
      missing_fields: []
    )

    assert_not issue.valid?
    assert_includes issue.errors[:duplicate_transaction].join, "must be present"
  end

  test "rejects unsupported missing fields" do
    issue = @workspace.import_issues.build(
      parsing_session: @session,
      source_type: "image_upload",
      missing_fields: [ "memo" ]
    )

    assert_not issue.valid?
    assert_includes issue.errors[:missing_fields].join, "unsupported"
  end

  test "parsing session must belong to workspace" do
    other_session = workspaces(:other_workspace).parsing_sessions.create!(
      source_type: "file_upload",
      status: "completed",
      review_status: "pending_review"
    )
    issue = @workspace.import_issues.build(
      parsing_session: other_session,
      source_type: "image_upload",
      missing_fields: [ "date" ]
    )

    assert_not issue.valid?
    assert_includes issue.errors[:parsing_session_id].join, "same workspace"
  end

  test "processed file must belong to workspace" do
    other_file = workspaces(:other_workspace).processed_files.create!(
      filename: "other.png",
      original_filename: "other.png",
      status: "completed"
    )
    issue = @workspace.import_issues.build(
      parsing_session: @session,
      processed_file: other_file,
      source_type: "image_upload",
      missing_fields: [ "date" ]
    )

    assert_not issue.valid?
    assert_includes issue.errors[:processed_file_id].join, "same workspace"
  end

  test "resolved transaction must belong to workspace" do
    other_transaction = workspaces(:other_workspace).transactions.create!(
      date: Date.current,
      amount: 10_000
    )
    issue = @workspace.import_issues.build(
      parsing_session: @session,
      resolved_transaction: other_transaction,
      source_type: "image_upload",
      missing_fields: [ "date" ]
    )

    assert_not issue.valid?
    assert_includes issue.errors[:resolved_transaction_id].join, "same workspace"
  end

  test "duplicate transaction must belong to workspace" do
    other_transaction = workspaces(:other_workspace).transactions.create!(
      date: Date.current,
      amount: 10_000
    )
    issue = @workspace.import_issues.build(
      parsing_session: @session,
      duplicate_transaction: other_transaction,
      source_type: "image_upload",
      issue_type: "ambiguous_duplicate",
      missing_fields: []
    )

    assert_not issue.valid?
    assert_includes issue.errors[:duplicate_transaction_id].join, "same workspace"
  end

  test "destroying resolved transaction keeps repair audit record" do
    transaction = @workspace.transactions.create!(
      date: Date.current,
      amount: 10_000
    )
    issue = @workspace.import_issues.create!(
      parsing_session: @session,
      resolved_transaction: transaction,
      source_type: "image_upload",
      missing_fields: [ "date" ],
      status: "resolved"
    )

    transaction.destroy!

    assert_nil issue.reload.resolved_transaction_id
  end
end
