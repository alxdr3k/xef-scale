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

  # Codex hotfix D: 음수 환불/취소·coupon 거래를 제외한다.

  test "ignores transactions with non-positive amount (refund/cancellation)" do
    # 같은 merchant에 환불(음수)만 있으면 반복 결제로 보지 않는다.
    3.times do |i|
      Transaction.create!(
        workspace: @workspace, merchant: "음수환불상점",
        amount: -5000, date: Date.current - i.months,
        status: "committed", deleted: false
      )
    end

    detector = RecurringPaymentDetector.new(@workspace)
    merchants = detector.detect.map { |r| r[:merchant] }
    assert_not_includes merchants, "음수환불상점"
  end

  test "average and last_amount exclude refund rows from same merchant" do
    # 양수 17000원 거래가 매월 있고, 가장 최근에 환불(음수)이 추가된 경우.
    # last_amount는 환불이 아니라 가장 최근 양수 거래의 amount여야 한다.
    Transaction.create!(
      workspace: @workspace, merchant: "넷플릭스",
      amount: -17000, date: Date.current + 1.day, # 가장 최근 (환불)
      status: "committed", deleted: false
    )

    detector = RecurringPaymentDetector.new(@workspace)
    netflix = detector.detect.find { |r| r[:merchant] == "넷플릭스" }
    assert_not_nil netflix
    assert_equal 17000, netflix[:average_amount], "음수가 평균에 섞이면 안 됨"
    assert_equal 17000, netflix[:last_amount], "last_amount는 가장 최근 양수 거래"
  end

  test "excludes coupon payment_type from aggregation" do
    3.times do |i|
      Transaction.create!(
        workspace: @workspace, merchant: "쿠폰상점",
        amount: 10000, date: Date.current - i.months,
        payment_type: "coupon",
        status: "committed", deleted: false
      )
    end

    detector = RecurringPaymentDetector.new(@workspace)
    merchants = detector.detect.map { |r| r[:merchant] }
    assert_not_includes merchants, "쿠폰상점"
  end
end
