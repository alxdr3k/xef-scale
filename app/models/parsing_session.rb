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
    completed? && review_pending?
  end

  def can_rollback?
    completed? && review_committed?
  end

  def can_discard?
    completed? && review_pending?
  end

  def commit_all!(user)
    return false unless can_commit?

    ActiveRecord::Base.transaction do
      transactions.pending_review.find_each do |tx|
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
      transactions.pending_review.destroy_all
      update!(review_status: "discarded")
    end
    true
  end

  def reviewable_transactions
    transactions.reviewable.order(date: :desc)
  end

  def pending_transaction_count
    transactions.pending_review.count
  end

  after_commit :broadcast_status_update, if: -> {
    saved_change_to_status? || saved_change_to_review_status?
  }

  private

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
