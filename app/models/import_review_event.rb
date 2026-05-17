class ImportReviewEvent < ApplicationRecord
  EVENT_TYPES = %w[transaction_updated session_committed session_rolled_back session_discarded].freeze

  belongs_to :workspace
  belongs_to :parsing_session
  belongs_to :reviewed_transaction, class_name: "Transaction", optional: true,
             inverse_of: :import_review_events

  serialize :changed_fields, coder: JSON

  before_validation :normalize_changed_fields

  validates :event_type, inclusion: { in: EVENT_TYPES }

  scope :transaction_updates, -> { where(event_type: "transaction_updated") }
  scope :session_terminations, -> { where(event_type: %w[session_committed session_rolled_back session_discarded]) }

  def transaction_updated?
    event_type == "transaction_updated"
  end

  private

  def normalize_changed_fields
    self.changed_fields = Array(changed_fields).map(&:to_s).select(&:present?).uniq
  end
end
