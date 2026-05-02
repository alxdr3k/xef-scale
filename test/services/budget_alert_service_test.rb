require "test_helper"

class BudgetAlertServiceTest < ActiveSupport::TestCase
  BUDGET = 500_000  # matches budgets(:main_budget).monthly_amount

  setup do
    @workspace = workspaces(:main_workspace)
    @budget = budgets(:main_budget)
    @admin = users(:admin)
    @member = users(:member)
    @reader = users(:reader)
    @year = 2025
    @month = 1
  end

  test "creates budget_warning alert when spending reaches 80 percent" do
    spend(@budget.monthly_amount * 0.8)

    assert_difference -> { Notification.count }, 3 do
      BudgetAlertService.new(@workspace).create_for_dates!([ Date.new(@year, @month, 15) ])
    end

    alert = Notification.order(:created_at).last
    assert_equal "budget_warning", alert.notification_type
    assert_equal @year, alert.target_year
    assert_equal @month, alert.target_month
  end

  test "creates budget_exceeded alert when spending is at 100 percent" do
    spend(@budget.monthly_amount)

    assert_difference -> { Notification.count }, 3 do
      BudgetAlertService.new(@workspace).create_for_dates!([ Date.new(@year, @month, 1) ])
    end

    assert_equal "budget_exceeded", Notification.order(:created_at).last.notification_type
  end

  test "does not create alert when spending is below 80 percent" do
    spend(@budget.monthly_amount * 0.79)

    assert_no_difference -> { Notification.count } do
      BudgetAlertService.new(@workspace).create_for_dates!([ Date.new(@year, @month, 15) ])
    end
  end

  test "does not duplicate alert for same member in same month" do
    spend(@budget.monthly_amount * 0.85)
    BudgetAlertService.new(@workspace).create_for_dates!([ Date.new(@year, @month, 15) ])
    count_after_first = Notification.count

    assert_no_difference -> { Notification.count } do
      BudgetAlertService.new(@workspace).create_for_dates!([ Date.new(@year, @month, 28) ])
    end
  end

  test "sends alerts to all workspace members including readers" do
    spend(@budget.monthly_amount * 0.8)
    BudgetAlertService.new(@workspace).create_for_dates!([ Date.new(@year, @month, 15) ])

    recipient_ids = Notification.where(notification_type: "budget_warning").pluck(:user_id)
    assert_includes recipient_ids, @admin.id
    assert_includes recipient_ids, @member.id
    assert_includes recipient_ids, @reader.id
  end

  test "skips when no dates provided" do
    assert_no_difference -> { Notification.count } do
      BudgetAlertService.new(@workspace).create_for_dates!([])
    end
  end

  test "skips when workspace has no budget" do
    @budget.destroy!
    @workspace.reload

    spend(400_000)
    assert_no_difference -> { Notification.count } do
      BudgetAlertService.new(@workspace).create_for_dates!([ Date.current ])
    end
  end

  test "deduplicates dates in the same month before checking" do
    spend(@budget.monthly_amount * 0.8)

    assert_difference -> { Notification.count }, 3 do
      BudgetAlertService.new(@workspace).create_for_dates!([
        Date.new(@year, @month, 1),
        Date.new(@year, @month, 15),
        Date.new(@year, @month, 31)
      ])
    end
  end

  test "class method create_for_transactions! extracts dates from transactions" do
    txns = [
      @workspace.transactions.create!(date: Date.new(@year, @month, 10), merchant: "A", amount: 400_000, status: "committed"),
      @workspace.transactions.create!(date: Date.new(@year, @month, 20), merchant: "B", amount: 5_000, status: "committed")
    ]

    assert_difference -> { Notification.count }, 3 do
      BudgetAlertService.create_for_transactions!(@workspace, txns)
    end

    assert_equal @month, Notification.order(:created_at).last.target_month
  end

  private

  def spend(amount)
    @workspace.transactions.create!(
      date: Date.new(@year, @month, 15),
      merchant: "테스트",
      amount: amount.to_i,
      status: "committed"
    )
  end
end
