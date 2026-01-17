class AllowanceTransaction < ApplicationRecord
  belongs_to :expense_transaction, class_name: 'Transaction'
  belongs_to :user

  validates :expense_transaction_id, uniqueness: { scope: :user_id }

  delegate :date, :amount, :merchant, :description, :category, to: :expense_transaction

  scope :for_user, ->(user) { where(user: user) }
  scope :for_month, ->(year, month) {
    joins(:expense_transaction).merge(Transaction.for_month(year, month))
  }

  def self.total_for_month(user, year, month)
    for_user(user).for_month(year, month)
      .joins(:expense_transaction)
      .sum('transactions.amount')
  end

  def self.mark_as_allowance!(transaction, user)
    create!(expense_transaction: transaction, user: user)
  end

  def self.unmark_as_allowance!(transaction, user)
    find_by(expense_transaction: transaction, user: user)&.destroy
  end
end
