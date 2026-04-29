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

    # Create another recurring merchant with variable amounts (>20% variance)
    [ 35000, 55000, 75000 ].each_with_index do |amt, i|
      Transaction.create!(
        workspace: @workspace,
        merchant: "KT 통신비",
        amount: amt,
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
    assert netflix.key?(:longest_streak)
    assert netflix.key?(:consistent_amount)
    assert netflix.key?(:consistent_day)
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

  test "does not include non-consecutive repeated merchants" do
    [ Date.new(2026, 1, 3), Date.new(2026, 3, 3) ].each do |date|
      Transaction.create!(
        workspace: @workspace,
        merchant: "계절 쇼핑몰",
        amount: 29_000,
        date: date,
        description: "비연속 구매",
        status: "committed",
        deleted: false
      )
    end

    detector = RecurringPaymentDetector.new(@workspace)
    results = detector.detect

    merchants = results.map { |r| r[:merchant] }
    assert_not_includes merchants, "계절 쇼핑몰"
  end

  test "does not include noisy repeated merchants without amount or day consistency" do
    [
      [ Date.new(2026, 1, 1), 5_000 ],
      [ Date.new(2026, 2, 20), 9_000 ],
      [ Date.new(2026, 3, 5), 4_000 ]
    ].each do |date, amount|
      Transaction.create!(
        workspace: @workspace,
        merchant: "랜덤 카페",
        amount: amount,
        date: date,
        description: "우연 반복",
        status: "committed",
        deleted: false
      )
    end

    detector = RecurringPaymentDetector.new(@workspace)
    results = detector.detect

    merchants = results.map { |r| r[:merchant] }
    assert_not_includes merchants, "랜덤 카페"
  end

  test "does not include coupon transactions" do
    2.times do |i|
      Transaction.create!(
        workspace: @workspace,
        merchant: "쿠폰 반복",
        amount: 10_000,
        date: Date.new(2026, i + 1, 10),
        description: "쿠폰",
        status: "committed",
        payment_type: "coupon",
        deleted: false
      )
    end

    detector = RecurringPaymentDetector.new(@workspace)
    results = detector.detect

    merchants = results.map { |r| r[:merchant] }
    assert_not_includes merchants, "쿠폰 반복"
  end

  test "uses latest transaction category" do
    Transaction.create!(
      workspace: @workspace,
      merchant: "카테고리 변경 구독",
      amount: 12_000,
      date: Date.new(2026, 1, 10),
      category: categories(:shopping),
      description: "old category",
      status: "committed",
      deleted: false
    )
    Transaction.create!(
      workspace: @workspace,
      merchant: "카테고리 변경 구독",
      amount: 12_000,
      date: Date.new(2026, 2, 10),
      category: categories(:food),
      description: "latest category",
      status: "committed",
      deleted: false
    )

    detector = RecurringPaymentDetector.new(@workspace)
    result = detector.detect.find { |r| r[:merchant] == "카테고리 변경 구독" }

    assert_equal "식비", result[:category]
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
