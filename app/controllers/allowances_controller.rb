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
end
