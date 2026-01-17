class Transaction < ApplicationRecord
  belongs_to :workspace
  belongs_to :category, optional: true
  belongs_to :financial_institution, optional: true
  belongs_to :parsing_session, optional: true
  belongs_to :committed_by, class_name: 'User', optional: true

  has_one :allowance_transaction, foreign_key: :expense_transaction_id, dependent: :destroy
  has_many :duplicate_confirmations_as_original, class_name: 'DuplicateConfirmation',
           foreign_key: :original_transaction_id, dependent: :destroy
  has_many :duplicate_confirmations_as_new, class_name: 'DuplicateConfirmation',
           foreign_key: :new_transaction_id, dependent: :destroy

  STATUSES = %w[pending_review committed rolled_back].freeze

  validates :date, presence: true
  validates :amount, presence: true, numericality: { only_integer: true }
  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where(deleted: false, status: 'committed') }
  scope :deleted, -> { where(deleted: true) }
  scope :pending_review, -> { where(status: 'pending_review') }
  scope :committed, -> { where(status: 'committed') }
  scope :rolled_back, -> { where(status: 'rolled_back') }
  scope :for_session, ->(session_id) { where(parsing_session_id: session_id) }
  scope :reviewable, -> { where(deleted: false).where.not(status: 'rolled_back') }
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

  def pending_review?
    status == 'pending_review'
  end

  def committed?
    status == 'committed'
  end

  def rolled_back?
    status == 'rolled_back'
  end

  def commit!(user)
    update!(status: 'committed', committed_at: Time.current, committed_by: user)
  end

  def rollback!
    update!(status: 'rolled_back')
  end

  def source_editable?
    financial_institution.nil? || financial_institution.identifier == 'unknown'
  end
end
