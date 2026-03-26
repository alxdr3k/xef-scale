require "test_helper"

class RecurringPaymentDetectorTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:main_workspace)

    # Create recurring transactions: same merchant, multiple months
    3.times do |i|
      Transaction.create!(
        workspace: @workspace,
        merchant: "넷플릭스",
        amount: 17000,
        date: Date.current - i.months,
        description: "NETFLIX",
        status: "committed",
        deleted: false
      )
    end

    # Create another recurring merchant with variable amounts
    3.times do |i|
      Transaction.create!(
        workspace: @workspace,
        merchant: "KT 통신비",
        amount: 50000 + (i * 5000),
        date: Date.current - i.months,
        description: "KT 요금",
        status: "committed",
        deleted: false
      )
    end
  end

  test "detects recurring merchants" do
    detector = RecurringPaymentDetector.new(@workspace)
    results = detector.detect

    merchants = results.map { |r| r[:merchant] }
    assert_includes merchants, "넷플릭스"
    assert_includes merchants, "KT 통신비"
  end

  test "returns correct fields for each result" do
    detector = RecurringPaymentDetector.new(@workspace)
    results = detector.detect

    netflix = results.find { |r| r[:merchant] == "넷플릭스" }
    assert_not_nil netflix

    assert netflix.key?(:merchant)
    assert netflix.key?(:occurrence_count)
    assert netflix.key?(:average_amount)
    assert netflix.key?(:last_amount)
    assert netflix.key?(:last_date)
    assert netflix.key?(:total_spent)
    assert netflix.key?(:consistent_amount)
  end

  test "identifies consistent amount correctly" do
    detector = RecurringPaymentDetector.new(@workspace)
    results = detector.detect

    netflix = results.find { |r| r[:merchant] == "넷플릭스" }
    assert netflix[:consistent_amount], "Netflix should be consistent (same amount every month)"

    kt = results.find { |r| r[:merchant] == "KT 통신비" }
    assert_not kt[:consistent_amount], "KT should not be consistent (variable amounts)"
  end

  test "does not include merchants with fewer than MIN_OCCURRENCES months" do
    Transaction.create!(
      workspace: @workspace,
      merchant: "한번만 가본 식당",
      amount: 15000,
      date: Date.current,
      description: "일회성",
      status: "committed",
      deleted: false
    )

    detector = RecurringPaymentDetector.new(@workspace)
    results = detector.detect

    merchants = results.map { |r| r[:merchant] }
    assert_not_includes merchants, "한번만 가본 식당"
  end

  test "does not include deleted transactions" do
    3.times do |i|
      Transaction.create!(
        workspace: @workspace,
        merchant: "삭제된 구독",
        amount: 10000,
        date: Date.current - i.months,
        description: "삭제됨",
        status: "committed",
        deleted: true
      )
    end

    detector = RecurringPaymentDetector.new(@workspace)
    results = detector.detect

    merchants = results.map { |r| r[:merchant] }
    assert_not_includes merchants, "삭제된 구독"
  end

  test "orders results by total_spent descending" do
    detector = RecurringPaymentDetector.new(@workspace)
    results = detector.detect

    totals = results.map { |r| r[:total_spent] }
    assert_equal totals, totals.sort.reverse
  end
end
