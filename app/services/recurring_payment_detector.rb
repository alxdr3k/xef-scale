class RecurringPaymentDetector
  MIN_OCCURRENCES = 2

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
                          Arel.sql("MAX(date) as last_date"),
                          Arel.sql("MAX(category_id) as last_category_id")
                        )
                        .group(:merchant)
                        .having("month_count >= ?", MIN_OCCURRENCES)
                        .order(Arel.sql("total_spent DESC"))

    # One query to load category names for all results
    category_ids = results.filter_map(&:last_category_id)
    categories = Category.where(id: category_ids).index_by(&:id)

    # Get last amount per merchant (single query)
    last_amounts = @workspace.transactions
                             .active
                             .excluding_coupon
                             .where(merchant: results.map(&:merchant))
                             .where("date = (SELECT MAX(t2.date) FROM transactions t2 WHERE t2.merchant = transactions.merchant AND t2.workspace_id = transactions.workspace_id AND t2.deleted = 0 AND t2.status = 'committed')")
                             .pluck(:merchant, :amount)
                             .to_h

    results.map do |row|
      avg = row.avg_amount.round
      variance = [ row.max_amount - avg, avg - row.min_amount ].max
      consistent = avg > 0 && variance <= (avg * 0.2)

      {
        merchant: row.merchant,
        occurrence_count: row.month_count,
        average_amount: avg,
        last_amount: last_amounts[row.merchant] || avg,
        last_date: Date.parse(row.last_date.to_s),
        total_spent: row.total_spent.to_i,
        consistent_amount: consistent,
        category: categories[row.last_category_id]&.name
      }
    end
  end
end
