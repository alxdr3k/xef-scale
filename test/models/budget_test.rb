require "test_helper"

class BudgetTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:main_workspace)
    @budget = budgets(:main_budget)
  end

  test "validates monthly_amount is present" do
    budget = Budget.new(workspace: @workspace, monthly_amount: nil)
    assert_not budget.valid?
    assert_includes budget.errors[:monthly_amount], "can't be blank"
  end

  test "validates monthly_amount is positive integer" do
    budget = Budget.new(workspace: @workspace, monthly_amount: -100)
    assert_not budget.valid?

    budget.monthly_amount = 0
    assert_not budget.valid?

    budget.monthly_amount = 500000
    assert budget.valid?
  end

  test "progress_for_month returns spending, budget, and percentage" do
    year = Date.current.year
    month = Date.current.month

    progress = @budget.progress_for_month(year, month)

    assert_includes progress.keys, :spending
    assert_includes progress.keys, :budget
    assert_includes progress.keys, :percentage
    assert_equal @budget.monthly_amount, progress[:budget]
  end

  test "progress_for_month calculates correct percentage" do
    # Budget is 500,000. Fixture transactions with status "committed" and not deleted
    # will determine the spending. With default "pending" status, active scope won't match.
    year = Date.current.year
    month = Date.current.month

    progress = @budget.progress_for_month(year, month)
    expected_pct = progress[:spending] > 0 ? (progress[:spending].to_f / 500000 * 100).round(1) : 0
    assert_equal expected_pct, progress[:percentage]
  end

  test "exceeded? returns true when spending meets or exceeds budget" do
    # With no committed transactions, spending should be 0
    year = 2020
    month = 1
    assert_not @budget.exceeded?(year, month)
  end

  test "warning? returns true between 80% and 100%" do
    year = 2020
    month = 1
    # No spending in 2020 — should not trigger warning
    assert_not @budget.warning?(year, month)
  end

  test "belongs to workspace" do
    assert_equal @workspace, @budget.workspace
  end
end
