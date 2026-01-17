class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :omniauthable, omniauth_providers: [:google_oauth2]

  has_many :owned_workspaces, class_name: 'Workspace', foreign_key: :owner_id, dependent: :destroy
  has_many :workspace_memberships, dependent: :destroy
  has_many :workspaces, through: :workspace_memberships
  has_many :allowance_transactions, dependent: :destroy
  has_many :sent_invitations, class_name: 'WorkspaceInvitation', foreign_key: :invited_by_id
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
      workspace_memberships.exists?(workspace: workspace, role: 'member_write')
  end

  def can_read?(workspace)
    can_write?(workspace) ||
      workspace_memberships.exists?(workspace: workspace, role: 'member_read')
  end

  def unread_notifications_count(workspace = nil)
    scope = notifications.unread
    scope = scope.for_workspace(workspace) if workspace
    scope.count
  end
end
