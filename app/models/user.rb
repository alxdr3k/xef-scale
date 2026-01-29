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

  # 금융기관별 명세서 비밀번호 관리
  def statement_password(institution_key)
    settings&.dig("statement_passwords", institution_key)
  end

  def set_statement_password(institution_key, password)
    self.settings ||= {}
    self.settings["statement_passwords"] ||= {}
    self.settings["statement_passwords"][institution_key] = password
  end

  # 지원하는 금융기관 목록 (비밀번호 필요한 것만)
  INSTITUTIONS_WITH_PASSWORD = {
    "shinhan_card" => "신한카드",
    "hana_card" => "하나카드"
  }.freeze
end
