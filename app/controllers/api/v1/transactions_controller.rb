module Api
  module V1
    class TransactionsController < BaseController
      before_action -> { require_scope!(:write) }, only: [ :create ]

      def create
        transaction = current_workspace.transactions.build(create_params)
        transaction.status = "committed"
        transaction.committed_at = Time.current
        transaction.source_type = "api"

        if transaction.save
          render json: { data: serialize_transaction(transaction) }, status: :created
        else
          render json: { error: transaction.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end

      def index
        transactions = current_workspace.transactions.active

        year = sanitize_year(params[:year])
        month = sanitize_month(params[:month])

        transactions = transactions.for_year(year) if year && month.nil?
        transactions = transactions.for_month(year || Date.current.year, month) if month
        transactions = transactions.by_category(params[:category_id]) if params[:category_id].present?
        transactions = transactions.by_institution(params[:institution_id]) if params[:institution_id].present?
        transactions = transactions.search(params[:q]) if params[:q].present?

        transactions = transactions.includes(:category, :financial_institution)
                                   .order(date: :desc)

        page = [ (params[:page] || 1).to_i, 1 ].max
        per_page = [ [ (params[:per_page] || 50).to_i, 1 ].max, 100 ].min
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

      include DateParamSanitization

      def create_params
        params.require(:transaction).permit(
          :date, :merchant, :amount, :notes,
          :category_id,
          :payment_type, :installment_month, :installment_total
        )
      end

      def serialize_transaction(t)
        {
          id: t.id,
          date: t.date.iso8601,
          merchant: t.merchant,
          amount: t.amount,
          category: t.category&.name,
          category_id: t.category_id,
          payment_type: t.payment_type,
          notes: t.notes,
          source_institution_raw: t.source_institution_raw,
          created_at: t.created_at.iso8601
        }
      end
    end
  end
end
