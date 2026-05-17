require "test_helper"

class ImportIssuesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:main_workspace)
    @user = users(:admin)
    @session = @workspace.parsing_sessions.create!(
      source_type: "file_upload",
      status: "completed",
      review_status: "pending_review"
    )
    @issue = @workspace.import_issues.create!(
      parsing_session: @session,
      source_type: "image_upload",
      missing_fields: %w[merchant amount]
    )
    sign_in @user
  end

  test "update with complete fields promotes the issue and redirects to review page" do
    patch workspace_import_issue_path(@workspace, @issue),
          params: { import_issue: { date: Date.current.iso8601, merchant: "스타벅스", amount: 5_000 } }

    assert_redirected_to review_workspace_parsing_session_path(@workspace, @session)
    follow_redirect!
    assert_equal "resolved", @issue.reload.status
    assert_not_nil @issue.resolved_transaction_id
  end

  test "update dismiss marks the issue dismissed" do
    patch workspace_import_issue_path(@workspace, @issue),
          params: { resolution_action: "dismiss" }

    assert_redirected_to review_workspace_parsing_session_path(@workspace, @session)
    assert_equal "dismissed", @issue.reload.status
  end

  test "read-only member cannot resolve issues" do
    sign_out @user
    sign_in users(:reader)

    patch workspace_import_issue_path(@workspace, @issue),
          params: { resolution_action: "dismiss" }

    assert_redirected_to root_path
    assert_equal "open", @issue.reload.status
  end

  test "cross-workspace issues are not reachable" do
    other_workspace = workspaces(:other_workspace)
    other_session = other_workspace.parsing_sessions.create!(
      source_type: "file_upload",
      status: "completed",
      review_status: "pending_review"
    )
    other_issue = other_workspace.import_issues.create!(
      parsing_session: other_session,
      source_type: "image_upload",
      missing_fields: %w[merchant]
    )

    patch workspace_import_issue_path(@workspace, other_issue),
          params: { resolution_action: "dismiss" }

    assert_response :not_found
    assert_equal "open", other_issue.reload.status
  end
end
