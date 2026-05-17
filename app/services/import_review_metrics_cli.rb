module ImportReviewMetricsCli
  module_function

  def parse(raw)
    out = { workspace_id: nil, since: nil, until: nil }
    raw.to_s.split(/\s+/).each do |token|
      next if token.empty?
      case token
      when /\A--workspace=(\d+)\z/
        out[:workspace_id] = $1.to_i
      when /\A--since=(\d{4}-\d{2}-\d{2})\z/
        out[:since] = safe_date($1)
      when /\A--until=(\d{4}-\d{2}-\d{2})\z/
        out[:until] = safe_date($1)
      end
    end
    out
  end

  # Regex matches calendar shapes but not validity (e.g. 2026-02-31). Swallow
  # invalid calendar dates and treat as "option not provided" so ad-hoc runs
  # don't crash on a typo.
  def safe_date(str)
    Date.parse(str)
  rescue Date::Error, ArgumentError
    nil
  end
end
