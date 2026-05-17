class ImportIssue < ApplicationRecord
  ISSUE_TYPES = %w[missing_required_fields ambiguous_duplicate].freeze
  STATUSES = %w[open resolved dismissed].freeze
  SOURCE_TYPES = %w[image_upload text_paste].freeze
  REQUIRED_FIELDS = %w[date merchant amount].freeze

  belongs_to :workspace
  belongs_to :parsing_session
  belongs_to :processed_file, optional: true
  belongs_to :duplicate_transaction, class_name: "Transaction", optional: true,
                                     inverse_of: :duplicate_import_issues
  belongs_to :resolved_transaction, class_name: "Transaction", optional: true,
                                    inverse_of: :resolved_import_issues

  serialize :missing_fields, coder: JSON
  serialize :raw_payload, coder: JSON

  before_validation :normalize_missing_fields

  validates :issue_type, inclusion: { in: ISSUE_TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :source_type, inclusion: { in: SOURCE_TYPES }
  validate :missing_fields_present
  validate :missing_fields_are_required_fields
  validate :duplicate_transaction_present_for_ambiguous_duplicate
  validate :source_matches_parsing_session
  validate :processed_file_matches_parsing_session
  validate :associations_belong_to_workspace

  scope :open, -> { where(status: "open") }
  scope :resolved, -> { where(status: "resolved") }
  scope :dismissed, -> { where(status: "dismissed") }
  scope :ambiguous_duplicates, -> { where(issue_type: "ambiguous_duplicate") }

  def open?
    status == "open"
  end

  def resolved?
    status == "resolved"
  end

  def dismissed?
    status == "dismissed"
  end

  def missing_required_fields?
    issue_type == "missing_required_fields"
  end

  def ambiguous_duplicate?
    issue_type == "ambiguous_duplicate"
  end

  def image_upload?
    source_type == "image_upload"
  end

  def text_paste?
    source_type == "text_paste"
  end

  private

  def normalize_missing_fields
    self.missing_fields = Array(missing_fields).map(&:to_s).select(&:present?).uniq
  end

  def missing_fields_present
    return unless missing_required_fields? && open?
    return if Array(missing_fields).any?

    errors.add(:missing_fields, "must include at least one missing field")
  end

  def missing_fields_are_required_fields
    invalid = Array(missing_fields).map(&:to_s) - REQUIRED_FIELDS
    return if invalid.empty?

    errors.add(:missing_fields, "contains unsupported fields: #{invalid.join(', ')}")
  end

  def duplicate_transaction_present_for_ambiguous_duplicate
    # Only enforce while the issue is open; resolved/dismissed issues remain
    # auditable even after their referenced transaction is destroyed (the
    # foreign key is nullified). Without this gate, stale audit records could
    # not be updated for status transitions.
    return unless ambiguous_duplicate? && open?
    return if duplicate_transaction.present?

    errors.add(:duplicate_transaction, "must be present for open ambiguous duplicates")
  end

  def source_matches_parsing_session
    return unless parsing_session

    if image_upload? && parsing_session.source_type != "file_upload"
      errors.add(:source_type, "must match a file upload parsing session")
    end

    if text_paste? && parsing_session.source_type != "text_paste"
      errors.add(:source_type, "must match a text paste parsing session")
    end
  end

  def processed_file_matches_parsing_session
    return unless parsing_session

    if text_paste? && processed_file.present?
      errors.add(:processed_file_id, "must be blank for text paste issues")
      return
    end

    return if processed_file.blank?
    return if parsing_session.processed_file_id == processed_file_id

    errors.add(:processed_file_id, "must match the parsing session processed file")
  end

  def associations_belong_to_workspace
    return if workspace_id.blank?

    if parsing_session && parsing_session.workspace_id != workspace_id
      errors.add(:parsing_session_id, "must belong to the same workspace")
    end

    if processed_file && processed_file.workspace_id != workspace_id
      errors.add(:processed_file_id, "must belong to the same workspace")
    end

    if duplicate_transaction && duplicate_transaction.workspace_id != workspace_id
      errors.add(:duplicate_transaction_id, "must belong to the same workspace")
    end

    return unless resolved_transaction && resolved_transaction.workspace_id != workspace_id

    errors.add(:resolved_transaction_id, "must belong to the same workspace")
  end
end
