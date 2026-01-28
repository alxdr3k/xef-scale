class AllowancesController < ApplicationController
  before_action :authenticate_user!

  def index
    @workspace = current_workspace
    @year = params[:year]&.to_i || Date.current.year
    @month = params[:month]&.to_i || Date.current.month

    @allowance_transactions = current_user.allowance_transactions
                                          .for_month(@year, @month)
                                          .includes(expense_transaction: [ :category, :financial_institution ])
                                          .order("transactions.date DESC")

    @total_amount = @allowance_transactions.joins(:expense_transaction).sum("transactions.amount")

    @monthly_totals = current_user.allowance_transactions
                                  .for_user(current_user)
                                  .joins(:expense_transaction)
                                  .where("transactions.date >= ?", Date.current.beginning_of_year)
                                  .group("strftime('%Y-%m', transactions.date)")
                                  .sum("transactions.amount")
  end

  def bulk_update
    transaction_ids = params[:transaction_ids].to_s.split(",").map(&:to_i).reject(&:zero?)

    if transaction_ids.empty?
      redirect_to allowances_path(year: params[:year], month: params[:month]), alert: "선택된 항목이 없습니다."
      return
    end

    action = params[:bulk_action]

    case action
    when "unmark_allowance"
      allowance_transactions = current_user.allowance_transactions
                                           .where(expense_transaction_id: transaction_ids)
      count = allowance_transactions.count
      allowance_transactions.find_each do |at|
        AllowanceTransaction.unmark_as_allowance!(at.expense_transaction, current_user)
      end
      notice = "#{count}건의 거래가 용돈에서 해제되었습니다."
    else
      notice = "알 수 없는 작업입니다."
    end

    redirect_to allowances_path(year: params[:year], month: params[:month]), notice: notice
  end
end
