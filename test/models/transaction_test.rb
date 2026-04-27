require "test_helper"

class TransactionTest < ActiveSupport::TestCase
  test "transaction is valid with valid attributes" do
    transaction = transactions(:food_transaction)
    assert transaction.valid?
  end

  test "transaction requires date" do
    transaction = Transaction.new(amount: 10000, workspace: workspaces(:main_workspace))
    assert_not transaction.valid?
    assert_includes transaction.errors[:date], "can't be blank"
  end

  test "transaction requires amount" do
    transaction = Transaction.new(date: Date.today, workspace: workspaces(:main_workspace))
    assert_not transaction.valid?
    assert_includes transaction.errors[:amount], "can't be blank"
  end

  test "transaction amount must be integer" do
    transaction = Transaction.new(
      date: Date.today,
      amount: 100.5,
      workspace: workspaces(:main_workspace)
    )
    assert_not transaction.valid?
    assert_includes transaction.errors[:amount], "must be an integer"
  end

  test "active scope excludes deleted transactions" do
    active_transactions = Transaction.active
    assert_includes active_transactions, transactions(:food_transaction)
    assert_not_includes active_transactions, transactions(:deleted_transaction)
  end

  test "deleted scope includes only deleted transactions" do
    deleted_transactions = Transaction.deleted
    assert_not_includes deleted_transactions, transactions(:food_transaction)
    assert_includes deleted_transactions, transactions(:deleted_transaction)
  end

  test "for_month scope filters by month" do
    year = Date.today.year
    month = Date.today.month
    transactions_this_month = Transaction.for_month(year, month)

    transactions_this_month.each do |t|
      assert_equal month, t.date.month
      assert_equal year, t.date.year
    end
  end

  test "search scope filters by merchant, description, or notes" do
    results = Transaction.search("마라탕")
    assert_includes results, transactions(:food_transaction)
    assert_not_includes results, transactions(:transport_transaction)
  end

  test "search scope returns all when query is blank" do
    results = Transaction.search("")
    assert_equal Transaction.count, results.count
  end

  test "soft_delete! sets deleted to true" do
    transaction = transactions(:food_transaction)
    transaction.soft_delete!
    assert transaction.reload.deleted
  end

  test "restore! sets deleted to false" do
    transaction = transactions(:deleted_transaction)
    transaction.restore!
    assert_not transaction.reload.deleted
  end

  test "formatted_date returns yyyy.mm.dd format" do
    transaction = Transaction.new(date: Date.new(2024, 1, 15))
    assert_equal "2024.01.15", transaction.formatted_date
  end

  test "formatted_amount adds comma separators" do
    transaction = Transaction.new(amount: 1234567)
    assert_equal "1,234,567", transaction.formatted_amount
  end

  test "month returns mm format" do
    transaction = Transaction.new(date: Date.new(2024, 3, 15))
    assert_equal "03", transaction.month
  end

  test "allowance? returns true when allowance_transaction exists" do
    transaction = transactions(:allowance_transaction_linked)
    assert transaction.allowance?
  end

  test "allowance? returns false when no allowance_transaction" do
    transaction = transactions(:transport_transaction)
    assert_not transaction.allowance?
  end

  test "by_category scope filters by category" do
    results = Transaction.by_category(categories(:food).id)
    results.each do |t|
      assert_equal categories(:food), t.category
    end
  end

  test "by_institution scope filters by financial institution" do
    results = Transaction.by_institution(financial_institutions(:shinhan_card).id)
    results.each do |t|
      assert_equal financial_institutions(:shinhan_card), t.financial_institution
    end
  end

  test "for_year scope filters by year" do
    year = Date.today.year
    transactions_this_year = Transaction.for_year(year)

    transactions_this_year.each do |t|
      assert_equal year, t.date.year
    end
  end

  test "by_category returns all when category_id is blank" do
    results = Transaction.by_category(nil)
    assert_equal Transaction.count, results.count
  end

  test "by_institution returns all when institution_id is blank" do
    results = Transaction.by_institution("")
    assert_equal Transaction.count, results.count
  end

  test "search scope handles nil query" do
    results = Transaction.search(nil)
    assert_equal Transaction.count, results.count
  end

  test "formatted_amount handles small numbers" do
    transaction = Transaction.new(amount: 99)
    assert_equal "99", transaction.formatted_amount
  end

  test "formatted_amount handles zero" do
    transaction = Transaction.new(amount: 0)
    assert_equal "0", transaction.formatted_amount
  end

  test "belongs to workspace" do
    transaction = transactions(:food_transaction)
    assert_equal workspaces(:main_workspace), transaction.workspace
  end

  test "belongs to category optionally" do
    transaction = Transaction.new(
      date: Date.today,
      amount: 1000,
      workspace: workspaces(:main_workspace)
    )
    assert transaction.valid?
  end

  test "has duplicate confirmations as original" do
    transaction = transactions(:food_transaction)
    # Creating a duplicate confirmation for testing
    DuplicateConfirmation.create!(
      parsing_session: parsing_sessions(:completed_session),
      original_transaction: transaction,
      new_transaction: transactions(:transport_transaction),
      status: "pending"
    )
    assert transaction.duplicate_confirmations_as_original.any?
  end

  test "category must belong to the same workspace" do
    transaction = Transaction.new(
      workspace: workspaces(:main_workspace),
      date: Date.current,
      amount: 1000,
      category: categories(:other_category)
    )
    assert_not transaction.valid?
    assert_includes transaction.errors[:category_id], "은(는) 같은 워크스페이스에 속해야 합니다"
  end

  test "category from same workspace is valid" do
    transaction = Transaction.new(
      workspace: workspaces(:main_workspace),
      date: Date.current,
      amount: 1000,
      category: categories(:food)
    )
    assert transaction.valid?
  end

  # --- financial institution is NOT a required domain field ---

  test "transaction is valid without financial institution" do
    transaction = Transaction.new(
      workspace: workspaces(:main_workspace),
      date: Date.current,
      amount: 5800,
      merchant: "스타벅스",
      status: "committed"
    )
    assert transaction.valid?, "금융기관 없이도 거래가 valid해야 합니다: #{transaction.errors.full_messages}"
  end

  test "source_institution_raw returns value from source_metadata" do
    transaction = transactions(:food_transaction)
    transaction.source_metadata = { "source_institution_raw" => "KB국민카드", "source_channel" => "pasted_text" }
    assert_equal "KB국민카드", transaction.source_institution_raw
  end

  test "source_institution_raw returns nil when source_metadata is blank" do
    transaction = Transaction.new(
      workspace: workspaces(:main_workspace),
      date: Date.current,
      amount: 1000
    )
    assert_nil transaction.source_institution_raw
  end

  test "source_channel returns channel from source_metadata" do
    transaction = transactions(:food_transaction)
    transaction.source_metadata = { "source_channel" => "pasted_text" }
    assert_equal "pasted_text", transaction.source_channel
  end

  test "source_editable? always returns false" do
    # Institution is import-only metadata; the inline dropdown is suppressed entirely
    transaction = transactions(:food_transaction)
    assert_not transaction.source_editable?

    transaction_no_institution = Transaction.new(
      workspace: workspaces(:main_workspace),
      date: Date.current,
      amount: 1000
    )
    assert_not transaction_no_institution.source_editable?
  end
end
