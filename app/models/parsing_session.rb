class ParsingSession < ApplicationRecord
  belongs_to :workspace
  belongs_to :processed_file
  has_many :duplicate_confirmations, dependent: :destroy
  has_many :transactions, class_name: 'Transaction'

  STATUSES = %w[pending processing completed failed].freeze

  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }
  scope :completed, -> { where(status: 'completed') }

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

  def start!
    update!(status: 'processing', started_at: Time.current)
  end

  def complete!(stats = {})
    update!(
      status: 'completed',
      completed_at: Time.current,
      total_count: stats[:total] || 0,
      success_count: stats[:success] || 0,
      duplicate_count: stats[:duplicate] || 0,
      error_count: stats[:error] || 0
    )
  end

  def fail!
    update!(status: 'failed', completed_at: Time.current)
  end

  def duration
    return nil unless started_at && completed_at
    completed_at - started_at
  end

  def has_duplicates?
    duplicate_count.to_i > 0
  end

  def pending_duplicates
    duplicate_confirmations.where(status: 'pending')
  end
end
