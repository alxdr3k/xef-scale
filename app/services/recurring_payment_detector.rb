class RecurringPaymentDetector
  MIN_OCCURRENCES = 2

  def initialize(workspace)
    @workspace = workspace
  end

  def detect
    # Codex hotfix D: 반복 결제 카드는 "월 예상 합계"를 보여주므로 분석 대상은
    # *양수 지출*만이어야 한다. 환불/취소(amount<0)와 coupon이 섞이면 평균/합계가
    # 오염되고, last_amount fallback이 부정확해진다.
    candidate_scope = @workspace.transactions
                                .active
                                .excluding_coupon
                                .where("amount > 0")
                                .where.not(merchant: [ nil, "" ])

    # Single query: get all candidate merchants with aggregated data
    results = candidate_scope
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

    # Codex hotfix D: last_amount subquery는 outer scope와 *동일* 필터를 써야
    # latest non-coupon positive expense의 amount를 가져온다. 과거 subquery는
    # status/deleted만 보고 payment_type/amount는 무시해서, 가장 최근 거래가
    # 환불/coupon이면 outer가 매칭에 실패해 avg fallback으로 떨어졌다.
    last_amounts = candidate_scope
                     .where(merchant: results.map(&:merchant))
                     .where("date = (SELECT MAX(t2.date) FROM transactions t2 " \
                            "WHERE t2.merchant = transactions.merchant " \
                            "AND t2.workspace_id = transactions.workspace_id " \
                            "AND t2.deleted = 0 AND t2.status = 'committed' " \
                            "AND t2.payment_type != 'coupon' AND t2.amount > 0)")
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
