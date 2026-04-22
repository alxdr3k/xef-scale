module DateParamSanitization
  extend ActiveSupport::Concern

  private

  # Validates a year param lives in the supported range before it hits
  # Date.new / for_year. Returns nil for blanks, non-integers, or out-of-range
  # values so callers can fall back to a default.
  def sanitize_year(value)
    return nil if value.blank?
    year = Integer(value.to_s, exception: false)
    return nil unless year && year.between?(2000, 2100)
    year
  end

  # Validates a month param is 1..12 before it hits Date.new / for_month.
  # Returns nil for anything else.
  def sanitize_month(value)
    return nil if value.blank?
    month = Integer(value.to_s, exception: false)
    return nil unless month && month.between?(1, 12)
    month
  end
end
