module Api
  module V1
    class SummariesController < BaseController
      before_action -> { require_scope!(:read) }

      def monthly
        year = (params[:year] || Date.current.year).to_i
        month = (params[:month] || Date.current.month).to_i

        unless (1..12).cover?(month) && year > 0
          return render json: { error: "Invalid year or month" }, status: :bad_request
        end

        transactions = current_workspace.transactions.active
                                        .for_month(year, month)
                                        .excluding_coupon

        total = transactions.sum(:amount)
        count = transactions.count

        category_breakdown = transactions
          .joins(:category)
          .group("categories.name")
          .order("SUM(transactions.amount) DESC")
          .pluck("categories.name", Arel.sql("SUM(transactions.amount)"), Arel.sql("COUNT(*)"))
          .map { |name, amount, cnt| { category: name, amount: amount.to_i, count: cnt } }

        render json: {
          data: {
            year: year,
            month: month,
            total_spending: total,
            transaction_count: count,
            daily_average: count > 0 ? (total.to_f / Date.new(year, month, 1).end_of_month.day).round : 0,
            category_breakdown: category_breakdown
          }
        }
      end

      def yearly
        year = (params[:year] || Date.current.year).to_i

        unless year > 0
          return render json: { error: "Invalid year" }, status: :bad_request
        end

        transactions = current_workspace.transactions.active
                                        .for_year(year)
                                        .excluding_coupon

        monthly_data = transactions
          .group(Arel.sql("strftime('%m', date)"))
          .order(Arel.sql("strftime('%m', date)"))
          .pluck(Arel.sql("strftime('%m', date)"), Arel.sql("SUM(amount)"), Arel.sql("COUNT(*)"))
          .map { |m, amount, cnt| { month: m.to_i, total: amount.to_i, count: cnt } }

        total = transactions.sum(:amount)

        render json: {
          data: {
            year: year,
            total_spending: total,
            monthly_average: monthly_data.any? ? (total.to_f / monthly_data.size).round : 0,
            months: monthly_data
          }
        }
      end
    end
  end
end
