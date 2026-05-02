class Transaction < ApplicationRecord
  belongs_to :workspace
  belongs_to :category, optional: true
  belongs_to :financial_institution, optional: true
  belongs_to :parsing_session, optional: true
  belongs_to :committed_by, class_name: "User", optional: true

  # source_metadata stores import/source hints as JSON.
  # Keys: source_channel, source_app_raw, source_institution_raw,
  #       source_sender_raw, parser_confidence
  # None of these fields are used for categorisation or budget calculations.
  store :source_metadata, coder: JSON

  has_one :allowance_transaction, foreign_key: :expense_transaction_id, dependent: :destroy
  has_many :comments, dependent: :destroy, inverse_of: :commentable_transaction
  has_many :duplicate_confirmations_as_original, class_name: "DuplicateConfirmation",
           foreign_key: :original_transaction_id, dependent: :destroy
  has_many :duplicate_confirmations_as_new, class_name: "DuplicateConfirmation",
           foreign_key: :new_transaction_id, dependent: :destroy
  has_many :duplicate_import_issues, class_name: "ImportIssue",
           foreign_key: :duplicate_transaction_id, dependent: :nullify,
           inverse_of: :duplicate_transaction
  has_many :resolved_import_issues, class_name: "ImportIssue",
           foreign_key: :resolved_transaction_id, dependent: :nullify,
           inverse_of: :resolved_transaction

  STATUSES = %w[pending_review committed rolled_back].freeze
  PAYMENT_TYPES = %w[lump_sum installment coupon].freeze
  SOURCE_TYPES = %w[manual text_paste image_upload api import].freeze

  enum :payment_type, {
    lump_sum: "lump_sum",
    installment: "installment",
    coupon: "coupon"
  }, default: :lump_sum

  validates :date, presence: true
  validates :amount, presence: true, numericality: { only_integer: true }
  validates :status, inclusion: { in: STATUSES }
  validates :payment_type, inclusion: { in: PAYMENT_TYPES }
  validates :source_type, inclusion: { in: SOURCE_TYPES }, allow_nil: true
  validates :parse_confidence,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 },
            allow_nil: true
  validate :category_belongs_to_workspace

  before_save :clear_installment_fields, if: -> { payment_type_changed? && payment_type != "installment" }

  scope :active, -> { where(deleted: false, status: "committed") }
  scope :deleted, -> { where(deleted: true) }
  scope :pending_review, -> { where(status: "pending_review") }
  scope :committed, -> { where(status: "committed") }
  scope :rolled_back, -> { where(status: "rolled_back") }
  scope :for_session, ->(session_id) { where(parsing_session_id: session_id) }
  scope :reviewable, -> { where(deleted: false).where.not(status: "rolled_back") }
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
    escaped = sanitize_sql_like(query)
    where("transactions.merchant LIKE ? OR transactions.notes LIKE ?",
          "%#{escaped}%", "%#{escaped}%")
  }
  scope :excluding_allowance, -> {
    where.not(id: AllowanceTransaction.select(:expense_transaction_id))
  }
  scope :excluding_coupon, -> { where.not(payment_type: "coupon") }
  scope :coupons_only, -> { where(payment_type: "coupon") }
  scope :with_duplicates, -> {
    join_condition = "INNER JOIN transactions t2 ON
      t1.id < t2.id AND
      t1.workspace_id = t2.workspace_id AND
      t1.date = t2.date AND
      t1.amount = t2.amount AND
      t1.status = 'committed' AND t2.status = 'committed' AND
      t1.deleted = false AND t2.deleted = false"

    sub1 = unscoped.select("t1.id").from("transactions t1").joins(join_condition)
    sub2 = unscoped.select("t2.id").from("transactions t1").joins(join_condition)

    where("transactions.id IN (#{sub1.to_sql}) OR transactions.id IN (#{sub2.to_sql})")
  }

  def soft_delete!
    update!(deleted: true)
  end

  def restore!
    update!(deleted: false)
  end

  def month
    date.strftime("%m")
  end

  def formatted_date
    date.strftime("%Y.%m.%d")
  end

  def formatted_amount
    amount.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
  end

  def allowance?
    allowance_transaction.present?
  end

  def pending_review?
    status == "pending_review"
  end

  def committed?
    status == "committed"
  end

  def rolled_back?
    status == "rolled_back"
  end

  def commit!(user)
    update!(status: "committed", committed_at: Time.current, committed_by: user)
  end

  def rollback!
    update!(status: "rolled_back")
  end

  # source_institution_raw: raw institution name captured during import (display-only)
  def source_institution_raw
    source_metadata&.fetch("source_institution_raw", nil)
  end

  # source_channel: how this transaction entered the system (pasted_text, screenshot, manual)
  def source_channel
    source_metadata&.fetch("source_channel", nil)
  end

  def source_editable?
    # The institution_cell dropdown is only shown when the institution is
    # unknown/absent; now that financial_institution is purely optional metadata
    # on committed transactions, we suppress this entirely for imported rows.
    false
  end

  def installment?
    installment_total.present? && installment_total > 1
  end

  def installment_badge
    return nil unless installment?
    "할부 #{installment_month}/#{installment_total}회차"
  end

  def payment_type_badge
    case payment_type
    when "installment"
      if installment_total.present? && installment_month.present?
        "할부 #{installment_month}/#{installment_total}회차"
      else
        "할부"
      end
    when "coupon"
      "소비쿠폰"
    else
      nil # 일시불은 표시 안함 (기본값이므로)
    end
  end

  private

  def clear_installment_fields
    self.installment_month = nil
    self.installment_total = nil
  end

  def category_belongs_to_workspace
    return if category_id.blank?
    return if category && workspace_id && category.workspace_id == workspace_id
    errors.add(:category_id, "은(는) 같은 워크스페이스에 속해야 합니다")
  end
end
