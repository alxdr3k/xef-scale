class ProcessedFile < ApplicationRecord
  include Turbo::Broadcastable

  belongs_to :workspace
  belongs_to :uploaded_by, class_name: "User", optional: true
  has_one :parsing_session, dependent: :destroy
  has_one_attached :file

  STATUSES = %w[pending processing completed failed].freeze

  validates :filename, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: "pending") }
  scope :completed, -> { where(status: "completed") }
  scope :failed, -> { where(status: "failed") }

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

  def mark_processing!
    update!(status: "processing")
  end

  def mark_completed!
    update!(status: "completed")
  end

  def mark_failed!
    update!(status: "failed")
  end

  after_commit :broadcast_removal, if: -> {
    saved_change_to_status? && %w[completed failed].include?(status)
  }

  private

  def broadcast_removal
    broadcast_remove_to(workspace, target: "pending_file_row_#{id}")
    broadcast_remove_to(workspace, target: "pending_file_card_#{id}")
  end
end
