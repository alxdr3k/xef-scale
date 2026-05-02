class Notification < ApplicationRecord
  include Turbo::Broadcastable

  belongs_to :user
  belongs_to :workspace
  belongs_to :notifiable, polymorphic: true, optional: true

  TYPES = %w[
    parsing_complete
    parsing_failed
    import_repair_needed
    commit_complete
    rollback_complete
    ocr_complete
    budget_warning
    budget_exceeded
  ].freeze

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
    has_reviewable_rows = parsing_session.review_pending? &&
                          parsing_session.transactions.pending_review.where(deleted: false).exists?
    open_issue_count = parsing_session.open_import_issues.count

    action_url = if has_reviewable_rows
      "/workspaces/#{parsing_session.workspace_id}/parsing_sessions/#{parsing_session.id}/review"
    else
      "/workspaces/#{parsing_session.workspace_id}/transactions"
    end
    message = if has_reviewable_rows
      "#{parsing_session.processed_file&.filename || '텍스트 붙여넣기'}에서 #{parsing_session.success_count}건의 거래가 발견되었습니다. 검토해주세요."
    elsif parsing_session.success_count.to_i.zero? && open_issue_count.positive?
      "#{parsing_session.processed_file&.filename || '텍스트 붙여넣기'}에서 수정이 필요한 항목 #{open_issue_count}건을 찾았습니다."
    elsif parsing_session.success_count.to_i.zero? && parsing_session.duplicate_count.to_i.positive?
      "#{parsing_session.processed_file&.filename || '텍스트 붙여넣기'}에서 이미 등록된 중복 항목 #{parsing_session.duplicate_count}건을 건너뛰었습니다."
    else
      "#{parsing_session.processed_file&.filename || '텍스트 붙여넣기'}에서 #{parsing_session.success_count}건의 거래가 장부에 등록되었습니다."
    end

    create!(
      user: user,
      workspace: parsing_session.workspace,
      notification_type: "parsing_complete",
      title: "파일 파싱 완료",
      message: message,
      action_url: action_url,
      notifiable: parsing_session
    )
  end

  def self.create_import_repair_needed!(parsing_session, user)
    issue_count = parsing_session.open_import_issues.count
    return if issue_count.zero?

    duplicate_count = parsing_session.open_import_issues.where(issue_type: "ambiguous_duplicate").count
    missing_count = issue_count - duplicate_count
    detail = if duplicate_count.positive? && missing_count.positive?
      "필수 정보가 부족하거나 중복 확인이 필요한 항목"
    elsif duplicate_count.positive?
      "중복 확인이 필요한 항목"
    else
      "필수 정보가 부족한 항목"
    end

    create!(
      user: user,
      workspace: parsing_session.workspace,
      notification_type: "import_repair_needed",
      title: "수정 필요한 결제",
      message: "#{parsing_session.processed_file&.filename || '가져오기'}에서 #{detail} #{issue_count}건이 있습니다.",
      action_url: "/workspaces/#{parsing_session.workspace_id}/transactions?repair=required&import_session_id=#{parsing_session.id}",
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

  def self.create_budget_alert!(workspace, user, type, progress, year:, month:)
    amount_str = progress[:spending].to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
    budget_str = progress[:budget].to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse

    create!(
      user: user,
      workspace: workspace,
      notification_type: type,
      title: type == "budget_exceeded" ? "예산 초과" : "예산 경고",
      message: "#{year}년 #{month}월 지출 ₩#{amount_str} / 예산 ₩#{budget_str} (#{progress[:percentage]}%)",
      action_url: "/dashboard",
      target_year: year,
      target_month: month
    )
  end

  after_commit :broadcast_badge_update, on: [ :create, :update ]
  after_commit :broadcast_import_repair_toast, on: :create

  private

  def broadcast_badge_update
    broadcast_replace_to(
      user,
      target: "notification-badge",
      partial: "notifications/badge",
      locals: { user: user, workspace: workspace }
    )
  end

  def broadcast_import_repair_toast
    return unless notification_type == "import_repair_needed"

    broadcast_prepend_to(
      user,
      target: "flash",
      partial: "shared/toast",
      locals: {
        type: "warning",
        message: message,
        action_url: action_url,
        action_label: "수정하기"
      }
    )
  end
end
