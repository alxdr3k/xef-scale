class ImportIssue < ApplicationRecord
  STATUSES = %w[open resolved dismissed].freeze
  SOURCE_TYPES = %w[image_upload text_paste].freeze
  REQUIRED_FIELDS = %w[date merchant amount].freeze

  belongs_to :workspace
  belongs_to :parsing_session
  belongs_to :processed_file, optional: true
  belongs_to :resolved_transaction, class_name: "Transaction", optional: true,
                                    inverse_of: :resolved_import_issues

  serialize :missing_fields, coder: JSON
  serialize :raw_payload, coder: JSON

  before_validation :normalize_missing_fields

  validates :status, inclusion: { in: STATUSES }
  validates :source_type, inclusion: { in: SOURCE_TYPES }
  validate :missing_fields_present
  validate :missing_fields_are_required_fields
  validate :associations_belong_to_workspace

  scope :open, -> { where(status: "open") }
  scope :resolved, -> { where(status: "resolved") }
  scope :dismissed, -> { where(status: "dismissed") }

  def open?
    status == "open"
  end

  def resolved?
    status == "resolved"
  end

  def dismissed?
    status == "dismissed"
  end

  private

  def normalize_missing_fields
    self.missing_fields = Array(missing_fields).map(&:to_s).select(&:present?).uniq
  end

  def missing_fields_present
    return if Array(missing_fields).any?

    errors.add(:missing_fields, "must include at least one missing field")
  end

  def missing_fields_are_required_fields
    invalid = Array(missing_fields).map(&:to_s) - REQUIRED_FIELDS
    return if invalid.empty?

    errors.add(:missing_fields, "contains unsupported fields: #{invalid.join(', ')}")
  end

  def associations_belong_to_workspace
    return if workspace_id.blank?

    if parsing_session && parsing_session.workspace_id != workspace_id
      errors.add(:parsing_session_id, "must belong to the same workspace")
    end

    if processed_file && processed_file.workspace_id != workspace_id
      errors.add(:processed_file_id, "must belong to the same workspace")
    end

    return unless resolved_transaction && resolved_transaction.workspace_id != workspace_id

    errors.add(:resolved_transaction_id, "must belong to the same workspace")
  end
end
