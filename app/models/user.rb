class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :omniauthable, omniauth_providers: [ :google_oauth2 ]

  serialize :settings, coder: JSON

  has_many :owned_workspaces, class_name: "Workspace", foreign_key: :owner_id, dependent: :destroy
  has_many :workspace_memberships, dependent: :destroy
  has_many :workspaces, through: :workspace_memberships
  has_many :allowance_transactions, dependent: :destroy
  has_many :sent_invitations, class_name: "WorkspaceInvitation", foreign_key: :invited_by_id
  has_many :comments, dependent: :destroy
  has_many :notifications, dependent: :destroy

  validates :email, presence: true, uniqueness: true

  def self.from_omniauth(auth)
    where(provider: auth.provider, uid: auth.uid).first_or_create do |user|
      user.email = auth.info.email
      user.password = Devise.friendly_token[0, 20]
      user.name = auth.info.name
      user.avatar_url = auth.info.image
    end
  end

  def admin_of?(workspace)
    workspace.owner_id == id ||
      workspace_memberships.exists?(workspace: workspace, role: %w[owner co_owner])
  end

  def can_write?(workspace)
    admin_of?(workspace) ||
      workspace_memberships.exists?(workspace: workspace, role: "member_write")
  end

  def can_read?(workspace)
    can_write?(workspace) ||
      workspace_memberships.exists?(workspace: workspace, role: "member_read")
  end

  def unread_notifications_count(workspace = nil)
    scope = notifications.unread
    scope = scope.for_workspace(workspace) if workspace
    scope.count
  end

  # 통합 명세서 비밀번호 (생년월일 6자리)
  # 기존 per-institution 비밀번호가 있으면 fallback으로 사용
  def statement_password
    settings&.dig("statement_password") ||
      settings&.dig("statement_passwords")&.values&.first
  end

  def set_statement_password(password)
    self.settings ||= {}
    self.settings["statement_password"] = password
  end

  # 카드사 출금 제외 (은행 통장 파싱 시)
  def exclude_card_withdrawals?
    settings&.dig("exclude_card_withdrawals") == true
  end

  def set_exclude_card_withdrawals(value)
    self.settings ||= {}
    self.settings["exclude_card_withdrawals"] = ActiveModel::Type::Boolean.new.cast(value)
  end

  # 제외할 거래처 목록
  def excluded_merchants
    settings&.dig("excluded_merchants") || []
  end

  def set_excluded_merchants(text)
    self.settings ||= {}
    self.settings["excluded_merchants"] = text.to_s.split("\n").map(&:strip).reject(&:blank?)
  end
end
