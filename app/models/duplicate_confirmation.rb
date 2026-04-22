class DuplicateConfirmation < ApplicationRecord
  belongs_to :parsing_session
  belongs_to :original_transaction, class_name: "Transaction"
  belongs_to :new_transaction, class_name: "Transaction"

  STATUSES = %w[pending keep_both keep_original keep_new].freeze
  DECISIONS = %w[keep_both keep_original keep_new].freeze

  validates :status, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: "pending") }
  scope :resolved, -> { where.not(status: "pending") }

  def pending?
    status == "pending"
  end

  def resolved?
    !pending?
  end

  # Decision setters only record the user's choice. Side effects on the
  # underlying transactions are applied by ParsingSession#commit_all! so that
  # the import review boundary is not crossed until the session is committed.
  # Discarding or rolling back the session must be able to cleanly undo or
  # skip these effects without data loss.

  def keep_both!
    update!(status: "keep_both")
  end

  def keep_original!
    update!(status: "keep_original")
  end

  def keep_new!
    update!(status: "keep_new")
  end

  def resolve!(decision)
    decision = decision.to_s
    raise ArgumentError, "Invalid decision: #{decision}" unless DECISIONS.include?(decision)
    update!(status: decision)
  end
end
