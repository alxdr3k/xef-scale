class DuplicateConfirmation < ApplicationRecord
  belongs_to :parsing_session
  belongs_to :original_transaction, class_name: "Transaction"
  belongs_to :new_transaction, class_name: "Transaction"

  STATUSES = %w[pending keep_both keep_original keep_new].freeze

  validates :status, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: "pending") }
  scope :resolved, -> { where.not(status: "pending") }

  def pending?
    status == "pending"
  end

  def resolved?
    !pending?
  end

  def keep_both!
    update!(status: "keep_both")
  end

  def keep_original!
    new_transaction.soft_delete!
    update!(status: "keep_original")
  end

  def keep_new!
    original_transaction.soft_delete!
    update!(status: "keep_new")
  end

  def resolve!(decision)
    case decision.to_s
    when "keep_both" then keep_both!
    when "keep_original" then keep_original!
    when "keep_new" then keep_new!
    else
      raise ArgumentError, "Invalid decision: #{decision}"
    end
  end
end
