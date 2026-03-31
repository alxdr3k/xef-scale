class Budget < ApplicationRecord
  belongs_to :workspace

  validates :monthly_amount, presence: true, numericality: { greater_than: 0, only_integer: true }

  def spending_for_month(year, month)
    workspace.transactions.active.excluding_coupon.for_month(year, month).sum(:amount)
  end

  def progress_for_month(year, month)
    spending = spending_for_month(year, month)
    percentage = monthly_amount > 0 ? (spending.to_f / monthly_amount * 100).round(1) : 0
    { spending: spending, budget: monthly_amount, percentage: percentage }
  end

  def exceeded?(year, month)
    spending_for_month(year, month) >= monthly_amount
  end

  def warning?(year, month)
    spending = spending_for_month(year, month)
    spending >= (monthly_amount * 0.8) && spending < monthly_amount
  end
end
