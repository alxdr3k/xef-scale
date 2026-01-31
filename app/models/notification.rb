class Notification < ApplicationRecord
  include Turbo::Broadcastable

  belongs_to :user
  belongs_to :workspace
  belongs_to :notifiable, polymorphic: true, optional: true

  TYPES = %w[parsing_complete parsing_failed commit_complete rollback_complete ocr_complete].freeze

  validates :notification_type, inclusion: { in: TYPES }
  validates :title, presence: true

  scope :unread, -> { where(read_at: nil) }
  scope :read, -> { where.not(read_at: nil) }
  scope :recent, -> { order(created_at: :desc) }
  scope :for_workspace, ->(workspace) { where(workspace: workspace) }

  def read?
    read_at.present?
  end

  def unread?
    !read?
  end

  def mark_as_read!
    update!(read_at: Time.current) if unread?
  end

  def self.mark_all_read!(user, workspace = nil)
    scope = unread.where(user: user)
    scope = scope.for_workspace(workspace) if workspace
    scope.update_all(read_at: Time.current)
  end

  def self.create_parsing_complete!(parsing_session, user)
    create!(
      user: user,
      workspace: parsing_session.workspace,
      notification_type: "parsing_complete",
      title: "파일 파싱 완료",
      message: "#{parsing_session.processed_file&.filename || '텍스트 붙여넣기'}에서 #{parsing_session.success_count}건의 거래가 발견되었습니다. 검토해주세요.",
      action_url: "/workspaces/#{parsing_session.workspace_id}/parsing_sessions/#{parsing_session.id}/review",
      notifiable: parsing_session
    )
  end

  def self.create_parsing_failed!(parsing_session, user)
    create!(
      user: user,
      workspace: parsing_session.workspace,
      notification_type: "parsing_failed",
      title: "파일 파싱 실패",
      message: "#{parsing_session.processed_file&.filename || '텍스트 붙여넣기'}를 파싱할 수 없습니다. 지원하지 않는 형식이거나 거래 내역이 없습니다.",
      notifiable: parsing_session
    )
  end

  after_commit :broadcast_badge_update, on: [ :create, :update ]

  private

  def broadcast_badge_update
    broadcast_replace_to(
      user,
      target: "notification-badge",
      partial: "notifications/badge",
      locals: { user: user, workspace: workspace }
    )
  end
end
