require "test_helper"

class AllowanceTransactionTest < ActiveSupport::TestCase
  test "allowance transaction is valid with valid attributes" do
    allowance = allowance_transactions(:admin_allowance)
    assert allowance.valid?
  end

  test "allowance requires expense_transaction" do
    allowance = AllowanceTransaction.new(user: users(:admin))
    assert_not allowance.valid?
    assert_includes allowance.errors[:expense_transaction], "must exist"
  end

  test "allowance requires user" do
    allowance = AllowanceTransaction.new(expense_transaction: transactions(:food_transaction))
    assert_not allowance.valid?
    assert_includes allowance.errors[:user], "must exist"
  end

  test "user can only have one allowance per transaction" do
    existing = allowance_transactions(:admin_allowance)
    allowance = AllowanceTransaction.new(
      expense_transaction: existing.expense_transaction,
      user: existing.user
    )
    assert_not allowance.valid?
    assert_includes allowance.errors[:expense_transaction_id], "has already been taken"
  end

  test "delegates date to expense_transaction" do
    allowance = allowance_transactions(:admin_allowance)
    assert_equal allowance.expense_transaction.date, allowance.date
  end

  test "delegates amount to expense_transaction" do
    allowance = allowance_transactions(:admin_allowance)
    assert_equal allowance.expense_transaction.amount, allowance.amount
  end

  test "for_user scope filters by user" do
    allowances = AllowanceTransaction.for_user(users(:admin))
    allowances.each do |a|
      assert_equal users(:admin), a.user
    end
  end

  test "mark_as_allowance! creates allowance transaction" do
    transaction = transactions(:transport_transaction)
    user = users(:member)

    assert_difference "AllowanceTransaction.count", 1 do
      AllowanceTransaction.mark_as_allowance!(transaction, user)
    end

    allowance = AllowanceTransaction.last
    assert_equal transaction, allowance.expense_transaction
    assert_equal user, allowance.user
  end

  test "unmark_as_allowance! destroys allowance transaction" do
    allowance = allowance_transactions(:admin_allowance)
    transaction = allowance.expense_transaction
    user = allowance.user

    assert_difference "AllowanceTransaction.count", -1 do
      AllowanceTransaction.unmark_as_allowance!(transaction, user)
    end
  end

  test "unmark_as_allowance! does nothing when allowance does not exist" do
    transaction = transactions(:transport_transaction)
    user = users(:member)

    assert_no_difference "AllowanceTransaction.count" do
      AllowanceTransaction.unmark_as_allowance!(transaction, user)
    end
  end

  test "total_for_month sums amounts for user and month" do
    user = users(:admin)
    year = Date.current.year
    month = Date.current.month

    total = AllowanceTransaction.total_for_month(user, year, month)
    assert_kind_of Integer, total
  end

  test "delegates merchant to expense_transaction" do
    allowance = allowance_transactions(:admin_allowance)
    assert_equal allowance.expense_transaction.merchant, allowance.merchant
  end

  test "delegates description to expense_transaction" do
    allowance = allowance_transactions(:admin_allowance)
    assert_equal allowance.expense_transaction.description, allowance.description
  end

  test "delegates category to expense_transaction" do
    allowance = allowance_transactions(:admin_allowance)
    assert_equal allowance.expense_transaction.category, allowance.category
  end

  test "for_month scope filters by year and month" do
    year = Date.current.year
    month = Date.current.month
    allowances = AllowanceTransaction.for_month(year, month)

    allowances.each do |a|
      assert_equal year, a.date.year
      assert_equal month, a.date.month
    end
  end
end
