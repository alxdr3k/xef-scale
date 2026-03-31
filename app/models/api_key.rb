class ApiKey < ApplicationRecord
  VALID_SCOPES = %w[read write].freeze

  belongs_to :workspace

  validates :name, presence: true
  validates :key_digest, presence: true, uniqueness: true
  validate :validate_scopes

  scope :active, -> { where(revoked_at: nil) }

  attr_accessor :raw_key

  def self.generate(workspace:, name:, scopes: "read")
    raw_key = "xef_#{SecureRandom.hex(24)}"
    api_key = create!(
      workspace: workspace,
      name: name,
      scopes: scopes,
      key_digest: hmac_digest(raw_key),
      key_prefix: raw_key[0, 8]
    )
    api_key.raw_key = raw_key
    api_key
  end

  def scope_list
    scopes.to_s.split(",").map(&:strip)
  end

  def has_scope?(scope)
    scope_list.include?(scope.to_s)
  end

  def self.authenticate(token)
    return nil if token.blank?
    digest = hmac_digest(token)
    key = active.find_by(key_digest: digest)
    if key && (key.last_used_at.nil? || key.last_used_at < 1.hour.ago)
      key.update_column(:last_used_at, Time.current)
    end
    key
  end

  def self.hmac_digest(value)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, value)
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  def revoked?
    revoked_at.present?
  end

  private

  def validate_scopes
    return if scopes.blank?
    invalid = scope_list - VALID_SCOPES
    errors.add(:scopes, "contains invalid scopes: #{invalid.join(', ')}") if invalid.any?
  end
end
