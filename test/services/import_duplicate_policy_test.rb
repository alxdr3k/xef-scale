require "test_helper"

class ImportDuplicatePolicyTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:main_workspace)
    @session = @workspace.parsing_sessions.create!(
      source_type: "text_paste",
      status: "processing",
      review_status: "pending_review"
    )
  end

  test "different installment totals are ambiguous duplicates not exact skips" do
    existing = @workspace.transactions.create!(
      date: Date.new(2026, 3, 25),
      merchant: "스타벅스강남점",
      amount: 12_000,
      payment_type: "installment",
      installment_month: 1,
      installment_total: 3,
      status: "committed"
    )
    staged = @workspace.transactions.create!(
      date: existing.date,
      merchant: existing.merchant,
      amount: existing.amount,
      payment_type: "installment",
      installment_month: 1,
      installment_total: 6,
      status: "pending_review",
      parsing_session: @session,
      source_type: "text_paste"
    )

    result = nil
    assert_difference -> { @workspace.import_issues.count }, 1 do
      result = ImportDuplicatePolicy.new(
        workspace: @workspace,
        parsing_session: @session,
        source_type: "text_paste"
      ).apply(staged)
    end

    assert result.repair_issue?
    assert_not Transaction.exists?(staged.id)

    issue = @workspace.import_issues.last
    assert issue.ambiguous_duplicate?
    assert_equal existing, issue.duplicate_transaction
  end
end
