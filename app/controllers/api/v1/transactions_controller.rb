module Api
  module V1
    class TransactionsController < BaseController
      def index
        transactions = current_workspace.transactions.active

        transactions = transactions.for_year(params[:year]) if params[:year].present?
        transactions = transactions.for_month(params[:year] || Date.current.year, params[:month]) if params[:month].present?
        transactions = transactions.by_category(params[:category_id]) if params[:category_id].present?
        transactions = transactions.by_institution(params[:institution_id]) if params[:institution_id].present?
        transactions = transactions.search(params[:q]) if params[:q].present?

        transactions = transactions.includes(:category, :financial_institution)
                                   .order(date: :desc)

        page = (params[:page] || 1).to_i
        per_page = [(params[:per_page] || 50).to_i, 100].min
        offset = (page - 1) * per_page

        total = transactions.count
        records = transactions.offset(offset).limit(per_page)

        render json: {
          data: records.map { |t| serialize_transaction(t) },
          meta: {
            total: total,
            page: page,
            per_page: per_page,
            total_pages: (total.to_f / per_page).ceil
          }
        }
      end

      def show
        transaction = current_workspace.transactions.active.find(params[:id])
        render json: { data: serialize_transaction(transaction) }
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Transaction not found" }, status: :not_found
      end

      private

      def serialize_transaction(t)
        {
          id: t.id,
          date: t.date.iso8601,
          merchant: t.merchant,
          amount: t.amount,
          category: t.category&.name,
          category_id: t.category_id,
          institution: t.financial_institution&.name,
          institution_id: t.financial_institution_id,
          payment_type: t.payment_type,
          notes: t.notes,
          created_at: t.created_at.iso8601
        }
      end
    end
  end
end
