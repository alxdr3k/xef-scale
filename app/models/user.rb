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

  # 제외할 거래처 목록
  def excluded_merchants
    settings&.dig("excluded_merchants") || []
  end

  def set_excluded_merchants(text)
    self.settings ||= {}
    self.settings["excluded_merchants"] = text.to_s.split("\n").map(&:strip).reject(&:blank?)
  end

  # ADR-0008 / Phase 5: 다크 모드 선호도. `users.settings` JSON에 저장
  # ("auto" / "light" / "dark"). 기본 `auto` — OS prefers-color-scheme 따름.
  # 다른 저장 위치(별도 users.theme 컬럼) 대신 JSON에 둔 이유: open-questions Q4
  # 결정. 별도 컬럼은 마이그레이션 비용 있고, 같은 settings JSON에 이미
  # excluded_merchants가 있으므로 user 단위 환경설정의 일관성을 위해 동일 위치.
  THEMES = %w[auto light dark].freeze

  def theme
    raw = settings&.dig("theme")
    THEMES.include?(raw) ? raw : "auto"
  end

  def theme=(value)
    self.settings ||= {}
    self.settings["theme"] = THEMES.include?(value.to_s) ? value.to_s : "auto"
  end
end
