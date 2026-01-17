class Transaction < ApplicationRecord
  belongs_to :workspace
  belongs_to :category, optional: true
  belongs_to :financial_institution, optional: true

  has_one :allowance_transaction, foreign_key: :expense_transaction_id, dependent: :destroy
  has_many :duplicate_confirmations_as_original, class_name: 'DuplicateConfirmation',
           foreign_key: :original_transaction_id, dependent: :destroy
  has_many :duplicate_confirmations_as_new, class_name: 'DuplicateConfirmation',
           foreign_key: :new_transaction_id, dependent: :destroy

  validates :date, presence: true
  validates :amount, presence: true, numericality: { only_integer: true }

  scope :active, -> { where(deleted: false) }
  scope :deleted, -> { where(deleted: true) }
  scope :for_month, ->(year, month) {
    start_date = Date.new(year.to_i, month.to_i, 1)
    end_date = start_date.end_of_month
    where(date: start_date..end_date)
  }
  scope :for_year, ->(year) {
    start_date = Date.new(year.to_i, 1, 1)
    end_date = start_date.end_of_year
    where(date: start_date..end_date)
  }
  scope :by_category, ->(category_id) { where(category_id: category_id) if category_id.present? }
  scope :by_institution, ->(institution_id) { where(financial_institution_id: institution_id) if institution_id.present? }
  scope :search, ->(query) {
    return all if query.blank?
    where('merchant LIKE ? OR description LIKE ? OR notes LIKE ?',
          "%#{query}%", "%#{query}%", "%#{query}%")
  }

  def soft_delete!
    update!(deleted: true)
  end

  def restore!
    update!(deleted: false)
  end

  def month
    date.strftime('%m')
  end

  def formatted_date
    date.strftime('%Y.%m.%d')
  end

  def formatted_amount
    amount.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
  end

  def allowance?
    allowance_transaction.present?
  end
end
