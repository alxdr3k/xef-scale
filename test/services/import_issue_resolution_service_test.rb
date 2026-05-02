require "test_helper"

class ImportIssueResolutionServiceTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:main_workspace)
    @user = users(:admin)
    @session = @workspace.parsing_sessions.create!(
      source_type: "file_upload",
      status: "processing",
      review_status: "pending_review"
    )
  end

  # ---------------------------------------------------------------------------
  # update_missing_fields!
  # ---------------------------------------------------------------------------

  test "update_missing_fields! saves partial fields and keeps issue open" do
    issue = create_issue(missing_fields: %w[date amount], date: nil, amount: nil)
    service = ImportIssueResolutionService.new(issue, user: @user)

    result = service.update_missing_fields!(date: "2026-04-01", merchant: "스타벅스", amount: "")

    assert result.success?
    assert_not result.transaction_committed?
    assert_equal :updated, result.status
    assert issue.reload.open?
    assert_equal Date.new(2026, 4, 1), issue.date
    assert_equal %w[amount], issue.missing_fields
  end

  test "update_missing_fields! promotes to committed transaction when all fields filled" do
    issue = create_issue(missing_fields: %w[date], date: nil, merchant: "네이버페이", amount: 12_000)
    service = ImportIssueResolutionService.new(issue, user: @user)

    result = nil
    assert_difference -> { @workspace.transactions.committed.count }, 1 do
      result = service.update_missing_fields!(date: Date.current.to_s, merchant: "네이버페이", amount: "12000")
    end

    assert result.success?
    assert result.transaction_committed?
    assert_equal :promoted, result.status
    assert issue.reload.resolved?
    assert_equal @user, issue.resolved_transaction.committed_by
  end

  test "update_missing_fields! fails on already resolved issue" do
    issue = create_issue(missing_fields: %w[date], date: nil, merchant: "스타벅스", amount: 5_000)
    issue.update!(status: "resolved")

    result = ImportIssueResolutionService.new(issue, user: @user)
                                         .update_missing_fields!(date: Date.current.to_s)

    assert_not result.success?
    assert_equal :invalid, result.status
  end

  test "update_missing_fields! fails for ambiguous_duplicate type" do
    committed = create_committed_transaction(merchant: "스타벅스", amount: 5_000, date: Date.current)
    issue = create_issue(
      issue_type: "ambiguous_duplicate",
      missing_fields: [],
      merchant: "스타벅스",
      amount: 5_000,
      date: Date.current,
      duplicate_transaction: committed
    )

    result = ImportIssueResolutionService.new(issue, user: @user)
                                         .update_missing_fields!(date: Date.current.to_s)

    assert_not result.success?
    assert_equal :invalid, result.status
  end

  # ---------------------------------------------------------------------------
  # promote_as_new!
  # ---------------------------------------------------------------------------

  test "promote_as_new! creates committed transaction from ambiguous duplicate issue" do
    committed = create_committed_transaction(merchant: "스타벅스 강남", amount: 5_000, date: Date.current)
    issue = create_issue(
      issue_type: "ambiguous_duplicate",
      missing_fields: [],
      merchant: "스타벅스 강남역",
      amount: 5_000,
      date: Date.current,
      duplicate_transaction: committed
    )

    result = nil
    assert_difference -> { @workspace.transactions.committed.count }, 1 do
      result = ImportIssueResolutionService.new(issue, user: @user).promote_as_new!
    end

    assert result.success?
    assert result.transaction_committed?
    assert_equal :promoted, result.status
    assert issue.reload.resolved?
  end

  test "promote_as_new! fails for missing_required_fields issue" do
    issue = create_issue(missing_fields: %w[date], date: nil, merchant: "스타벅스", amount: 5_000)

    result = ImportIssueResolutionService.new(issue, user: @user).promote_as_new!

    assert_not result.success?
    assert_equal :invalid, result.status
  end

  # ---------------------------------------------------------------------------
  # dismiss!
  # ---------------------------------------------------------------------------

  test "dismiss! marks issue as dismissed" do
    issue = create_issue(missing_fields: %w[date], date: nil, merchant: "스타벅스", amount: 5_000)
    service = ImportIssueResolutionService.new(issue, user: @user)

    result = nil
    assert_no_difference -> { @workspace.transactions.count } do
      result = service.dismiss!
    end

    assert result.success?
    assert_not result.transaction_committed?
    assert_equal :dismissed, result.status
    assert issue.reload.dismissed?
  end

  test "dismiss! fails on already dismissed issue" do
    issue = create_issue(missing_fields: %w[date], date: nil, merchant: "스타벅스", amount: 5_000)
    issue.update!(status: "dismissed")

    result = ImportIssueResolutionService.new(issue, user: @user).dismiss!

    assert_not result.success?
  end

  # ---------------------------------------------------------------------------
  # Result helpers
  # ---------------------------------------------------------------------------

  test "transaction_committed? is true only for :promoted status" do
    assert ImportIssueResolutionService::Result.new(status: :promoted, message: "ok", transaction: nil).transaction_committed?
    assert_not ImportIssueResolutionService::Result.new(status: :updated, message: "ok", transaction: nil).transaction_committed?
    assert_not ImportIssueResolutionService::Result.new(status: :dismissed, message: "ok", transaction: nil).transaction_committed?
    assert_not ImportIssueResolutionService::Result.new(status: :ambiguous_duplicate, message: "ok", transaction: nil).transaction_committed?
    assert_not ImportIssueResolutionService::Result.new(status: :exact_duplicate_skipped, message: "ok", transaction: nil).transaction_committed?
  end

  test "success? covers updated promoted dismissed exact_duplicate_skipped ambiguous_duplicate" do
    %i[updated promoted dismissed exact_duplicate_skipped ambiguous_duplicate].each do |status|
      result = ImportIssueResolutionService::Result.new(status: status, message: "ok", transaction: nil)
      assert result.success?, "Expected success? for status=#{status}"
    end

    result = ImportIssueResolutionService::Result.new(status: :invalid, message: "err", transaction: nil)
    assert_not result.success?
  end

  private

  def create_issue(attributes)
    defaults = {
      parsing_session: @session,
      workspace: @workspace,
      source_type: "image_upload",
      issue_type: "missing_required_fields",
      status: "open",
      raw_payload: { "merchant" => attributes[:merchant] }
    }
    @workspace.import_issues.create!(defaults.merge(attributes))
  end

  def create_committed_transaction(merchant:, amount:, date:)
    @workspace.transactions.create!(
      merchant: merchant,
      amount: amount,
      date: date,
      status: "committed"
    )
  end
end
