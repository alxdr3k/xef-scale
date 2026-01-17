class ProcessedFile < ApplicationRecord
  belongs_to :workspace
  has_one :parsing_session, dependent: :destroy
  has_one_attached :file

  STATUSES = %w[pending processing completed failed].freeze

  validates :filename, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: 'pending') }
  scope :completed, -> { where(status: 'completed') }
  scope :failed, -> { where(status: 'failed') }

  def pending?
    status == 'pending'
  end

  def processing?
    status == 'processing'
  end

  def completed?
    status == 'completed'
  end

  def failed?
    status == 'failed'
  end

  def mark_processing!
    update!(status: 'processing')
  end

  def mark_completed!
    update!(status: 'completed')
  end

  def mark_failed!
    update!(status: 'failed')
  end
end
