class RecurringPaymentDetector
  MIN_OCCURRENCES = 2
  CONSISTENT_DAY_WINDOW = 7

  def initialize(workspace)
    @workspace = workspace
  end

  def detect
    # Single query: get all candidate merchants with aggregated data
    results = @workspace.transactions
                        .active
                        .excluding_coupon
                        .where.not(merchant: [ nil, "" ])
                        .select(
                          :merchant,
                          Arel.sql("COUNT(*) as tx_count"),
                          Arel.sql("COUNT(DISTINCT strftime('%Y-%m', date)) as month_count"),
                          Arel.sql("SUM(amount) as total_spent"),
                          Arel.sql("AVG(amount) as avg_amount"),
                          Arel.sql("MAX(amount) as max_amount"),
                          Arel.sql("MIN(amount) as min_amount"),
                          Arel.sql("MAX(date) as last_date")
                        )
                        .group(:merchant)
                        .having("month_count >= ?", MIN_OCCURRENCES)
                        .order(Arel.sql("total_spent DESC"))

    transactions_by_merchant = candidate_transactions(results.map(&:merchant)).group_by(&:merchant)
    categories = Category.where(
      id: transactions_by_merchant.values.flatten.filter_map(&:category_id).uniq
    ).index_by(&:id)

    results.filter_map do |row|
      transactions = transactions_by_merchant.fetch(row.merchant, [])
      longest_streak = longest_consecutive_streak(month_keys(transactions))
      next if longest_streak < MIN_OCCURRENCES

      avg = row.avg_amount.round
      amount_consistent = consistent_amount?(avg, row.min_amount, row.max_amount)
      day_consistent = consistent_day?(transactions)
      next unless amount_consistent || day_consistent

      last_transaction = transactions.max_by { |tx| [ tx.date, tx.id ] }

      {
        merchant: row.merchant,
        occurrence_count: row.month_count.to_i,
        longest_streak: longest_streak,
        average_amount: avg,
        last_amount: last_transaction&.amount || avg,
        last_date: last_transaction&.date || Date.parse(row.last_date.to_s),
        total_spent: row.total_spent.to_i,
        consistent_amount: amount_consistent,
        consistent_day: day_consistent,
        category: categories[last_transaction&.category_id]&.name
      }
    end
  end

  private

  def candidate_transactions(merchants)
    return Transaction.none if merchants.empty?

    @workspace.transactions
              .active
              .excluding_coupon
              .where(merchant: merchants)
              .select(:id, :merchant, :amount, :date, :category_id)
  end

  def month_keys(transactions)
    transactions.map { |tx| tx.date.year * 12 + tx.date.month }.uniq.sort
  end

  def longest_consecutive_streak(keys)
    keys.each_with_object({ current: 0, best: 0, previous: nil }) do |key, streak|
      streak[:current] = key == streak[:previous].to_i + 1 ? streak[:current] + 1 : 1
      streak[:best] = [ streak[:best], streak[:current] ].max
      streak[:previous] = key
    end[:best]
  end

  def consistent_amount?(average, min_amount, max_amount)
    return false unless average.positive?

    variance = [ max_amount - average, average - min_amount ].max
    variance <= (average * 0.2)
  end

  def consistent_day?(transactions)
    days = transactions.map { |tx| tx.date.day }
    return false if days.empty?

    days.max - days.min <= CONSISTENT_DAY_WINDOW
  end
end
