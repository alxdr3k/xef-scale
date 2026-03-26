class RecurringPaymentDetector
  MIN_OCCURRENCES = 2

  def initialize(workspace)
    @workspace = workspace
  end

  def detect
    # Group committed active transactions by merchant + similar amount
    # Look for patterns where the same merchant charges similar amounts monthly
    candidates = @workspace.transactions
                           .active
                           .excluding_coupon
                           .where.not(merchant: [nil, ""])
                           .group(:merchant)
                           .having("COUNT(DISTINCT strftime('%Y-%m', date)) >= ?", MIN_OCCURRENCES)
                           .pluck(:merchant)

    patterns = candidates.filter_map { |merchant| analyze_merchant(merchant) }
    patterns.sort_by { |p| -p[:total_spent] }
  end

  private

  def analyze_merchant(merchant)
    transactions = @workspace.transactions
                             .active
                             .excluding_coupon
                             .where(merchant: merchant)
                             .order(date: :desc)

    months = transactions.map { |t| t.date.strftime("%Y-%m") }.uniq
    return nil if months.size < MIN_OCCURRENCES

    amounts = transactions.pluck(:amount)
    avg_amount = (amounts.sum.to_f / amounts.size).round
    amount_variance = amounts.map { |a| (a - avg_amount).abs }.max

    # Consider "recurring" if amount variance is within 20% of average
    consistent = amount_variance <= (avg_amount * 0.2)

    {
      merchant: merchant,
      occurrence_count: months.size,
      months: months,
      average_amount: avg_amount,
      last_amount: transactions.first.amount,
      last_date: transactions.first.date,
      total_spent: amounts.sum,
      consistent_amount: consistent,
      category: transactions.first.category&.name
    }
  end
end
