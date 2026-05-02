require "test_helper"

class ImportDuplicatePolicyTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:main_workspace)
    @other_workspace = workspaces(:other_workspace)
    @session = @workspace.parsing_sessions.create!(
      source_type: "text_paste",
      status: "processing",
      review_status: "pending_review"
    )
  end

  test "different installment totals are ambiguous duplicates not exact skips" do
    existing = committed(merchant: "스타벅스강남점", amount: 12_000,
                         payment_type: "installment", installment_month: 1, installment_total: 3)
    staged = staged_tx(date: existing.date, merchant: existing.merchant, amount: existing.amount,
                       payment_type: "installment", installment_month: 1, installment_total: 6)

    result = nil
    assert_difference -> { @workspace.import_issues.count }, 1 do
      result = policy.apply(staged)
    end

    assert result.repair_issue?
    assert_not Transaction.exists?(staged.id)
    issue = @workspace.import_issues.last
    assert issue.ambiguous_duplicate?
    assert_equal existing, issue.duplicate_transaction
  end

  test "exact same-session row is skipped without creating an import issue" do
    first = staged_tx(date: Date.new(2026, 4, 1), merchant: "스타벅스", amount: 5_000)
    second = staged_tx(date: Date.new(2026, 4, 1), merchant: "스타벅스", amount: 5_000)

    assert_no_difference -> { @workspace.import_issues.count } do
      result = policy.apply(second)
      assert result.skipped_exact_duplicate?
    end

    assert_not Transaction.exists?(second.id)
    assert Transaction.exists?(first.id)
  end

  test "exact duplicate against committed ledger transaction is skipped" do
    existing = committed(merchant: "카카오T", amount: 8_500)
    staged = staged_tx(date: existing.date, merchant: existing.merchant, amount: existing.amount)

    assert_no_difference -> { @workspace.import_issues.count } do
      result = policy.apply(staged)
      assert result.skipped_exact_duplicate?
    end

    assert_not Transaction.exists?(staged.id)
  end

  test "transaction from other workspace is not treated as a duplicate" do
    other_tx = @other_workspace.transactions.create!(
      date: Date.new(2026, 4, 1),
      merchant: "스타벅스",
      amount: 5_000,
      status: "committed"
    )
    staged = staged_tx(date: other_tx.date, merchant: other_tx.merchant, amount: other_tx.amount)

    result = policy.apply(staged)

    assert result.no_duplicate?
    assert Transaction.exists?(staged.id)
  end

  test "merchant normalization matches whitespace and case variants" do
    existing = committed(merchant: "스타벅스  강남점", amount: 5_000)
    staged = staged_tx(date: existing.date, merchant: "스타벅스강남점", amount: 5_000)

    assert_no_difference -> { @workspace.import_issues.count } do
      result = policy.apply(staged)
      assert result.skipped_exact_duplicate?
    end
  end

  test "empty merchant string matches empty merchant" do
    existing = committed(merchant: "", amount: 3_000)
    staged = staged_tx(date: existing.date, merchant: "", amount: 3_000)

    assert_no_difference -> { @workspace.import_issues.count } do
      result = policy.apply(staged)
      assert result.skipped_exact_duplicate?
    end
  end

  test "no duplicate returned when no matching transaction exists" do
    staged = staged_tx(date: Date.new(2025, 1, 1), merchant: "알수없는곳", amount: 99_999)

    result = policy.apply(staged)

    assert result.no_duplicate?
    assert Transaction.exists?(staged.id)
  end

  test "ambiguous duplicate creates ImportIssue and removes staged transaction together" do
    existing = committed(merchant: "스타벅스 강남", amount: 5_000)
    staged = staged_tx(date: existing.date, merchant: "스타벅스 강남역", amount: 5_000)

    assert_difference -> { @workspace.import_issues.count }, 1 do
      policy.apply(staged)
    end

    assert_not Transaction.exists?(staged.id)
    issue = @workspace.import_issues.last
    assert_equal existing, issue.duplicate_transaction
    assert_equal @session, issue.parsing_session
  end

  private

  def policy
    @policy ||= ImportDuplicatePolicy.new(
      workspace: @workspace,
      parsing_session: @session,
      source_type: "text_paste"
    )
  end

  def committed(merchant:, amount:, date: Date.new(2026, 4, 1), **attrs)
    @workspace.transactions.create!(
      { date: date, merchant: merchant, amount: amount, status: "committed" }.merge(attrs)
    )
  end

  def staged_tx(merchant:, amount:, date: Date.new(2026, 4, 1), **attrs)
    @workspace.transactions.create!(
      {
        date: date, merchant: merchant, amount: amount,
        status: "pending_review",
        parsing_session: @session,
        source_type: "text_paste"
      }.merge(attrs)
    )
  end
end
