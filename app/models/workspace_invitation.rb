class WorkspaceInvitation < ApplicationRecord
  belongs_to :workspace
  belongs_to :invited_by, class_name: 'User'

  validates :token, presence: true, uniqueness: true
  validates :max_uses, numericality: { greater_than: 0 }, allow_nil: true

  before_validation :generate_token, on: :create

  scope :active, -> { where('expires_at IS NULL OR expires_at > ?', Time.current) }
  scope :available, -> { active.where('max_uses IS NULL OR current_uses < max_uses') }

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  def used_up?
    max_uses.present? && current_uses >= max_uses
  end

  def usable?
    !expired? && !used_up?
  end

  def use!
    return false unless usable?
    increment!(:current_uses)
    true
  end

  private

  def generate_token
    self.token ||= SecureRandom.urlsafe_base64(32)
  end
end
