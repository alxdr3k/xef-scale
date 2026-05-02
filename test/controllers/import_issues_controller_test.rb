require "test_helper"

class ImportIssuesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:admin)
    @workspace = workspaces(:main_workspace)
    @parsing_session = parsing_sessions(:completed_session)
    sign_in @user
  end

  test "writer promotes completed missing field issue to committed transaction" do
    issue = create_missing_issue(missing_fields: [ "date" ], date: nil, merchant: "네이버페이", amount: 12_000)

    assert_difference -> { @workspace.transactions.committed.count }, 1 do
      patch workspace_import_issue_path(@workspace, issue),
            params: { import_issue: { date: Date.current, merchant: "네이버페이", amount: "12000" } }
    end

    assert_redirected_to workspace_transactions_path(@workspace, repair: "required", import_session_id: @parsing_session.id)
    assert issue.reload.resolved?
    assert issue.resolved_transaction.committed?
    assert_equal @user, issue.resolved_transaction.committed_by
    assert_equal "image_upload", issue.resolved_transaction.source_type
    assert_equal issue.id, issue.resolved_transaction.source_metadata["import_issue_id"]
  end

  test "writer can save partial repair values without promoting" do
    issue = create_missing_issue(missing_fields: [ "date", "amount" ], date: nil, merchant: "네이버페이", amount: nil)

    assert_no_difference -> { @workspace.transactions.count } do
      patch workspace_import_issue_path(@workspace, issue),
            params: { import_issue: { date: Date.current, merchant: "네이버페이", amount: "" } }
    end

    assert_redirected_to workspace_transactions_path(@workspace, repair: "required", import_session_id: @parsing_session.id)
    assert issue.reload.open?
    assert_equal Date.current, issue.date
    assert_equal [ "amount" ], issue.missing_fields
  end

  test "completed repair matching exact duplicate is skipped and dismissed" do
    duplicate = @workspace.transactions.create!(
      date: Date.current,
      merchant: "네이버페이",
      amount: 12_000,
      status: "committed"
    )
    issue = create_missing_issue(missing_fields: [ "date" ], date: nil, merchant: duplicate.merchant, amount: duplicate.amount)

    assert_no_difference -> { @workspace.transactions.count } do
      patch workspace_import_issue_path(@workspace, issue),
            params: { import_issue: { date: duplicate.date, merchant: duplicate.merchant, amount: duplicate.amount } }
    end

    assert issue.reload.dismissed?
    assert_nil issue.resolved_transaction
    assert_equal "exact_duplicate_skipped", issue.raw_payload.dig("repair_resolution", "resolution")
  end

  test "completed repair with ambiguous duplicate stays in repair queue for duplicate decision" do
    duplicate = @workspace.transactions.create!(
      date: Date.current,
      merchant: "스타벅스 강남",
      amount: 5_000,
      status: "committed"
    )
    issue = create_missing_issue(missing_fields: [ "date" ], date: nil, merchant: "스타벅스 강남역", amount: duplicate.amount)

    assert_no_difference -> { @workspace.transactions.count } do
      patch workspace_import_issue_path(@workspace, issue),
            params: { import_issue: { date: duplicate.date, merchant: issue.merchant, amount: issue.amount } }
    end

    assert issue.reload.open?
    assert issue.ambiguous_duplicate?
    assert_equal duplicate, issue.duplicate_transaction
    assert_empty issue.missing_fields
  end

  test "writer can register ambiguous duplicate as a new transaction" do
    duplicate = @workspace.transactions.create!(
      date: Date.current,
      merchant: "스타벅스 강남",
      amount: 5_000,
      status: "committed"
    )
    issue = @workspace.import_issues.create!(
      parsing_session: @parsing_session,
      source_type: "image_upload",
      issue_type: "ambiguous_duplicate",
      duplicate_transaction: duplicate,
      date: duplicate.date,
      merchant: "스타벅스 강남역",
      amount: duplicate.amount,
      missing_fields: []
    )

    assert_difference -> { @workspace.transactions.committed.count }, 1 do
      patch workspace_import_issue_path(@workspace, issue),
            params: { resolution_action: "create_new" }
    end

    assert issue.reload.resolved?
    assert issue.resolved_transaction.committed?
    assert_equal "스타벅스 강남역", issue.resolved_transaction.merchant
  end

  test "writer can dismiss repair issue" do
    issue = create_missing_issue(missing_fields: [ "date" ], date: nil, merchant: "네이버페이", amount: 12_000)

    assert_no_difference -> { @workspace.transactions.count } do
      patch workspace_import_issue_path(@workspace, issue),
            params: { resolution_action: "dismiss" }
    end

    assert issue.reload.dismissed?
  end

  test "reader cannot update repair issue" do
    sign_out @user
    sign_in users(:reader)
    issue = create_missing_issue(missing_fields: [ "date" ], date: nil, merchant: "네이버페이", amount: 12_000)

    assert_no_difference -> { @workspace.transactions.count } do
      patch workspace_import_issue_path(@workspace, issue),
            params: { import_issue: { date: Date.current, merchant: "네이버페이", amount: "12000" } }
    end

    assert_redirected_to workspace_path(@workspace)
    assert issue.reload.open?
  end

  private

  def create_missing_issue(attributes)
    @workspace.import_issues.create!(
      {
        parsing_session: @parsing_session,
        source_type: "image_upload",
        issue_type: "missing_required_fields",
        raw_payload: { "merchant" => attributes[:merchant] }
      }.merge(attributes)
    )
  end
end
