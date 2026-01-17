class WorkspaceMembership < ApplicationRecord
  belongs_to :user
  belongs_to :workspace

  ROLES = %w[owner co_owner member_write member_read].freeze

  validates :role, presence: true, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :workspace_id }

  scope :admins, -> { where(role: %w[owner co_owner]) }
  scope :writers, -> { where(role: %w[owner co_owner member_write]) }

  def admin?
    %w[owner co_owner].include?(role)
  end

  def writer?
    %w[owner co_owner member_write].include?(role)
  end
end
