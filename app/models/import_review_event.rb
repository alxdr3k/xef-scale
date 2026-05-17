class ImportReviewEvent < ApplicationRecord
  TRANSACTION_EVENTS = %w[transaction_updated transaction_excluded].freeze
  SESSION_TERMINATION_EVENTS = %w[session_committed session_rolled_back session_discarded].freeze
  EVENT_TYPES = (TRANSACTION_EVENTS + SESSION_TERMINATION_EVENTS).freeze

  belongs_to :workspace
  belongs_to :parsing_session
  belongs_to :reviewed_transaction, class_name: "Transaction", optional: true,
             inverse_of: :import_review_events

  serialize :changed_fields, coder: JSON

  before_validation :normalize_changed_fields

  validates :event_type, inclusion: { in: EVENT_TYPES }
  validate :reviewed_transaction_matches_event_type
  validate :changed_fields_match_event_type
  validate :associations_belong_to_workspace
  validate :reviewed_transaction_belongs_to_parsing_session

  scope :transaction_updates, -> { where(event_type: "transaction_updated") }
  scope :transaction_exclusions, -> { where(event_type: "transaction_excluded") }
  scope :session_terminations, -> { where(event_type: SESSION_TERMINATION_EVENTS) }

  def transaction_updated?
    event_type == "transaction_updated"
  end

  def transaction_excluded?
    event_type == "transaction_excluded"
  end

  def session_termination?
    SESSION_TERMINATION_EVENTS.include?(event_type)
  end

  private

  def normalize_changed_fields
    self.changed_fields = Array(changed_fields).map(&:to_s).select(&:present?).uniq
  end

  def reviewed_transaction_matches_event_type
    if TRANSACTION_EVENTS.include?(event_type) && reviewed_transaction.blank?
      errors.add(:reviewed_transaction, "must be present for #{event_type}")
    end

    if session_termination? && reviewed_transaction.present?
      errors.add(:reviewed_transaction, "must be blank for #{event_type}")
    end
  end

  def changed_fields_match_event_type
    if transaction_updated? && Array(changed_fields).empty?
      errors.add(:changed_fields, "must include at least one field for transaction_updated")
    end

    if session_termination? && Array(changed_fields).any?
      errors.add(:changed_fields, "must be empty for #{event_type}")
    end
  end

  def associations_belong_to_workspace
    return if workspace_id.blank?

    if parsing_session && parsing_session.workspace_id != workspace_id
      errors.add(:parsing_session_id, "must belong to the same workspace")
    end

    if reviewed_transaction && reviewed_transaction.workspace_id != workspace_id
      errors.add(:reviewed_transaction_id, "must belong to the same workspace")
    end
  end

  def reviewed_transaction_belongs_to_parsing_session
    return unless reviewed_transaction && parsing_session
    return if reviewed_transaction.parsing_session_id == parsing_session_id

    errors.add(:reviewed_transaction_id, "must belong to the parsing session")
  end
end
