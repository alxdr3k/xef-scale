require "test_helper"

class DuplicateDetectorTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:main_workspace)
  end

  test "returns nil when no candidate matches the amount" do
    new_tx = @workspace.transactions.create!(date: Date.current, amount: 12345, merchant: "고유 가맹점")
    assert_nil DuplicateDetector.new(@workspace, new_tx).find_match
  end

  test "scores same date + same amount + same merchant as high confidence" do
    @workspace.transactions.create!(date: Date.current, amount: 5_500, merchant: "스타벅스 강남점")
    new_tx = @workspace.transactions.create!(date: Date.current, amount: 5_500, merchant: "스타벅스 강남점")

    match = DuplicateDetector.new(@workspace, new_tx).find_match

    assert_equal "high", match.confidence
    assert_operator match.score, :>=, 90
  end

  test "scores merchant-only difference as medium when token overlap exists" do
    @workspace.transactions.create!(date: Date.current, amount: 8_000, merchant: "쿠팡 식료품")
    new_tx = @workspace.transactions.create!(date: Date.current, amount: 8_000, merchant: "쿠팡")

    match = DuplicateDetector.new(@workspace, new_tx).find_match

    assert_includes %w[high medium], match.confidence
  end

  test "scores date drift by one day with merchant mismatch as low or no match" do
    @workspace.transactions.create!(date: Date.current - 1.day, amount: 4_500, merchant: "전혀 다른 가게")
    new_tx = @workspace.transactions.create!(date: Date.current, amount: 4_500, merchant: "스타벅스")

    match = DuplicateDetector.new(@workspace, new_tx).find_match

    assert(match.nil? || match.confidence == "low",
           "expected nil or low confidence, got #{match&.confidence}")
  end

  test "ignores soft-deleted candidates" do
    existing = @workspace.transactions.create!(date: Date.current, amount: 7_000, merchant: "삭제된 가게")
    existing.soft_delete!
    new_tx = @workspace.transactions.create!(date: Date.current, amount: 7_000, merchant: "삭제된 가게")

    assert_nil DuplicateDetector.new(@workspace, new_tx).find_match
  end

  test "ignores candidates with a different installment_month" do
    @workspace.transactions.create!(
      date: Date.current, amount: 100_000, merchant: "노트북",
      payment_type: "installment", installment_month: 1, installment_total: 6
    )
    new_tx = @workspace.transactions.create!(
      date: Date.current, amount: 100_000, merchant: "노트북",
      payment_type: "installment", installment_month: 2, installment_total: 6
    )

    assert_nil DuplicateDetector.new(@workspace, new_tx).find_match
  end
end
