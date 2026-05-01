class ParsingSession < ApplicationRecord
  include Turbo::Broadcastable
  include ActionView::RecordIdentifier

  belongs_to :workspace
  belongs_to :processed_file, optional: true
  belongs_to :committed_by, class_name: "User", optional: true
  belongs_to :rolled_back_by, class_name: "User", optional: true
  has_many :duplicate_confirmations, dependent: :destroy
  has_many :transactions, dependent: :nullify
  has_many :notifications, as: :notifiable, dependent: :destroy

  STATUSES = %w[pending processing completed failed].freeze
  REVIEW_STATUSES = %w[pending_review committed rolled_back discarded].freeze
  SOURCE_TYPES = %w[file_upload text_paste].freeze
  INCOMPLETE_PARSE_NOTE_START_MARKER = "[[xef:incomplete_parse_rows]]".freeze
  INCOMPLETE_PARSE_NOTE_END_MARKER = "[[/xef:incomplete_parse_rows]]".freeze
  INCOMPLETE_PARSE_NOTE_BLOCK_PATTERN = /
    #{Regexp.escape(INCOMPLETE_PARSE_NOTE_START_MARKER)}
    \s*
    (.*?)
    \s*
    #{Regexp.escape(INCOMPLETE_PARSE_NOTE_END_MARKER)}
  /mx
  INCOMPLETE_PARSE_NOTE_STORAGE_PATTERN = /
    #{Regexp.escape(INCOMPLETE_PARSE_NOTE_START_MARKER)}
    \s*
    .*?
    \s*
    #{Regexp.escape(INCOMPLETE_PARSE_NOTE_END_MARKER)}
  /mx

  validates :status, inclusion: { in: STATUSES }
  validates :review_status, inclusion: { in: REVIEW_STATUSES }, allow_nil: true
  validates :source_type, inclusion: { in: SOURCE_TYPES }

  def text_paste?
    source_type == "text_paste"
  end

  def file_upload?
    source_type == "file_upload"
  end

  scope :recent, -> { order(created_at: :desc) }
  scope :completed, -> { where(status: "completed") }
  scope :pending_review, -> { where(review_status: "pending_review") }
  scope :review_committed, -> { where(review_status: "committed") }
  scope :needs_review, -> { completed.pending_review }

  def pending?
    status == "pending"
  end

  def processing?
    status == "processing"
  end

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end

  def start!
    update!(status: "processing", started_at: Time.current)
  end

  def complete!(stats = {})
    update!(
      status: "completed",
      completed_at: Time.current,
      total_count: stats[:total] || 0,
      success_count: stats[:success] || 0,
      duplicate_count: stats[:duplicate] || 0,
      error_count: stats[:error] || 0
    )
  end

  def fail!
    update!(status: "failed", completed_at: Time.current)
  end

  def duration
    return nil unless started_at && completed_at
    completed_at - started_at
  end

  def has_duplicates?
    duplicate_count.to_i > 0
  end

  def pending_duplicates
    duplicate_confirmations.where(status: "pending")
  end

  def has_unresolved_duplicates?
    pending_duplicates.exists?
  end

  def review_pending?
    review_status == "pending_review"
  end

  def review_committed?
    review_status == "committed"
  end

  def review_rolled_back?
    review_status == "rolled_back"
  end

  def review_discarded?
    review_status == "discarded"
  end

  def can_commit?
    completed? && review_pending? && !has_unresolved_duplicates?
  end

  def can_rollback?
    completed? && review_committed?
  end

  def can_discard?
    completed? && review_pending?
  end

  def self.incomplete_parse_note_block(note)
    [
      INCOMPLETE_PARSE_NOTE_START_MARKER,
      note.to_s.strip,
      INCOMPLETE_PARSE_NOTE_END_MARKER
    ].join("\n")
  end

  def incomplete_parse_note?
    file_upload? && incomplete_parse_note_blocks.any?
  end

  def incomplete_parse_note_text
    return nil unless file_upload?

    incomplete_parse_note_blocks.join("\n\n").presence
  end

  def user_visible_notes
    return notes.to_s.strip.presence unless file_upload?

    visible_notes = notes.to_s.gsub(INCOMPLETE_PARSE_NOTE_STORAGE_PATTERN, "").strip.presence
    visible_notes || failed_incomplete_parse_note_text
  end

  def notes_with_user_visible_text(user_notes)
    return user_notes.to_s.strip unless file_upload?

    visible_notes = user_notes.to_s.strip
    visible_notes = nil if visible_notes == failed_incomplete_parse_note_text

    [
      visible_notes.presence,
      *incomplete_parse_note_storage_blocks
    ].compact.join("\n\n")
  end

  def commit_all!(user)
    return false unless can_commit?

    with_lock do
      return false unless can_commit?

      apply_duplicate_decisions!
      transactions.pending_review.where(deleted: false).find_each do |tx|
        tx.commit!(user)
      end
      update!(
        review_status: "committed",
        committed_at: Time.current,
        committed_by: user
      )
    end
    true
  end

  def rollback_all!(user)
    return false unless can_rollback?

    ActiveRecord::Base.transaction do
      transactions.committed.where(parsing_session_id: id).find_each(&:rollback!)
      undo_duplicate_decisions!
      update!(
        review_status: "rolled_back",
        rolled_back_at: Time.current,
        rolled_back_by: user
      )
    end
    true
  end

  def discard_all!
    return false unless can_discard?

    ActiveRecord::Base.transaction do
      transactions.committed.find_each(&:rollback!)
      transactions.pending_review.destroy_all
      update!(review_status: "discarded")
    end
    true
  end

  def auto_commit_ready_transactions!(user: nil, has_import_exceptions: false)
    committed_transactions = []

    with_lock do
      ready_transactions_for_auto_commit.each do |tx|
        tx.commit!(user)
        committed_transactions << tx
      end

      mark_auto_committed!(user) if auto_commit_complete?(has_import_exceptions: has_import_exceptions)
    end

    committed_transactions
  end

  def reviewable_transactions
    transactions.reviewable.order(date: :desc)
  end

  def pending_transaction_count
    transactions.pending_review.count
  end

  # Snapshot of what this import actually did to the ledger after commit.
  # Used by the post-commit banner so the user can see the diff (committed
  # vs. excluded vs. duplicate decisions) instead of just a row count.
  def commit_summary
    {
      committed: transactions.committed.count,
      excluded: transactions.rolled_back.count,
      uncategorized: transactions.committed.where(category_id: nil).count,
      originals_replaced: duplicate_confirmations.where(status: "keep_new").count,
      originals_kept: duplicate_confirmations.where(status: "keep_original").count,
      duplicates_kept_both: duplicate_confirmations.where(status: "keep_both").count
    }
  end

  after_commit :broadcast_status_update, if: -> {
    saved_change_to_status? || saved_change_to_review_status?
  }

  private

  def incomplete_parse_note_blocks
    notes.to_s.scan(INCOMPLETE_PARSE_NOTE_BLOCK_PATTERN).flatten.map(&:strip).select(&:present?)
  end

  def incomplete_parse_note_storage_blocks
    notes.to_s.scan(INCOMPLETE_PARSE_NOTE_STORAGE_PATTERN).map(&:strip)
  end

  def failed_incomplete_parse_note_text
    return nil unless failed?

    incomplete_parse_note_text
  end

  def ready_transactions_for_auto_commit
    same_session_duplicate_keys = pending_same_session_duplicate_keys
    transactions.pending_review
                .where(deleted: false)
                .where.not(id: duplicate_confirmations.pending.select(:new_transaction_id))
                .reject { |tx| same_session_duplicate_keys.include?(auto_commit_dedup_key(tx)) }
                .select { |tx| import_required_fields_complete?(tx) }
  end

  def auto_commit_complete?(has_import_exceptions: false)
    return false if has_import_exceptions

    transactions.pending_review.where(deleted: false).none? && !has_unresolved_duplicates?
  end

  def mark_auto_committed!(user)
    update!(
      review_status: "committed",
      committed_at: Time.current,
      committed_by: user
    )
  end

  def pending_same_session_duplicate_keys
    transactions.pending_review
                .where(deleted: false)
                .group_by { |tx| auto_commit_dedup_key(tx) }
                .select { |_key, rows| rows.size > 1 }
                .keys
  end

  def auto_commit_dedup_key(transaction)
    [
      transaction.date,
      transaction.amount,
      transaction.merchant.to_s.strip.gsub(/\s+/, "").downcase,
      transaction.installment_month
    ]
  end

  def import_required_fields_complete?(transaction)
    transaction.date.present? &&
      transaction.merchant.to_s.strip.present? &&
      transaction.amount.present? &&
      transaction.amount.to_i != 0
  end

  # Apply deferred duplicate-resolution decisions at commit time. Keeping the
  # side effects here (instead of in DuplicateConfirmation) ensures that
  # decisions made during review only affect the originals once the user
  # actually commits the import, so discarding the session leaves existing
  # committed data untouched.
  def apply_duplicate_decisions!
    duplicate_confirmations.resolved.find_each do |dc|
      new_tx = dc.new_transaction
      # If the user excluded the new transaction from this import (rolled back
      # or soft-deleted during review), the duplicate decision no longer
      # applies — there is no "new" row to keep, so the original should not be
      # touched even when the prior decision was keep_new.
      next if new_tx.rolled_back? || new_tx.deleted

      case dc.status
      when "keep_new"
        original = dc.original_transaction
        original.soft_delete! unless original.deleted?
      when "keep_original"
        # The new transaction is part of this session's pending_review set;
        # rolling it back keeps it out of the subsequent commit loop and out
        # of the `active` scope so no duplicate row is ever surfaced.
        new_tx.rollback! if new_tx.pending_review?
      end
    end
  end

  # Undo the side effects of apply_duplicate_decisions! for a rollback: any
  # originals that were soft-deleted because the user chose keep_new must be
  # restored now that the session's committed transactions are being rolled
  # back.
  def undo_duplicate_decisions!
    duplicate_confirmations.where(status: "keep_new").find_each do |dc|
      original = dc.original_transaction
      original.restore! if original.deleted?
    end
  end

  def broadcast_status_update
    # Desktop table row
    broadcast_replace_to(
      workspace,
      target: dom_id(self),
      partial: "parsing_sessions/parsing_session_row",
      locals: { parsing_session: self, workspace: workspace }
    )
    # Mobile card
    broadcast_replace_to(
      workspace,
      target: "#{dom_id(self)}_card",
      partial: "parsing_sessions/parsing_session_card",
      locals: { parsing_session: self, workspace: workspace }
    )
  end
end
