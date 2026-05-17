class ImportReviewMetricsReport
  def initialize(sessions:, options:)
    @sessions = sessions
    @session_ids = @sessions.pluck(:id)
    @options = options
  end

  def render
    [
      header,
      status_distribution,
      modification_rate,
      exclusion_rate,
      import_issue_distribution,
      commit_latency
    ].join("\n\n")
  end

  private

  def header
    [
      "# Import Review Metrics (Issue #187 baseline)",
      "Generated: #{Time.current.iso8601}",
      "Scope: #{scope_summary}",
      "Sessions in scope: #{@session_ids.size}"
    ].join("\n")
  end

  def scope_summary
    bits = []
    bits << (@options[:workspace_id] ? "workspace=#{@options[:workspace_id]}" : "all workspaces")
    bits << "since=#{@options[:since]}" if @options[:since]
    bits << "until=#{@options[:until]}" if @options[:until]
    bits.join(", ")
  end

  # status × review_status grid. ParsingSession#fail! only flips `status` and
  # leaves `review_status` at "pending_review", so a single-dimension breakdown
  # mis-labels failed/processing sessions as awaiting review.
  def status_distribution
    rows = ParsingSession
             .where(id: @session_ids)
             .group(:status, :review_status)
             .count
    total = rows.values.sum
    return "## Session status distribution\n  (no sessions in scope)" if total.zero?

    lines = [ "## Session status distribution (status × review_status)" ]
    rows.sort_by { |k, _| k }.each do |(status, review_status), n|
      pct = (100.0 * n / total).round(1)
      label = "#{status} / #{review_status}".ljust(32)
      lines << "  #{label} #{n.to_s.rjust(6)}  (#{pct}%)"
    end
    lines.join("\n")
  end

  def modification_rate
    return "## Row modification rate\n  (no committed sessions in scope)" if committed_ids.empty?

    # Align numerator + denominator with the codebase's `reviewable` scope
    # (`deleted: false` AND `status != "rolled_back"`). Rows the user excluded
    # mid-review or rows soft-deleted by retention should not skew the metric
    # in either direction.
    reviewable_per_session = reviewable_count_per_session
    reviewable_tx_ids = reviewable_transaction_ids

    modified_per_session = ImportReviewEvent
                             .where(parsing_session_id: committed_ids, event_type: "transaction_updated")
                             .where(reviewed_transaction_id: reviewable_tx_ids)
                             .distinct
                             .group(:parsing_session_id)
                             .count(:reviewed_transaction_id)

    rates = committed_ids.filter_map do |sid|
      total = reviewable_per_session[sid] || 0
      next nil if total.zero?
      (modified_per_session[sid] || 0).to_f / total
    end

    return "## Row modification rate\n  (no reviewable transactions in committed sessions)" if rates.empty?

    format_rate_section(
      title: "Row modification rate (distinct transaction / reviewable)",
      label: "modification",
      rates: rates,
      footer: "Issue #187 thresholds: <10% = C(auto-post) 후보 / 10–30% = B 유지 / >30% = A 강화"
    )
  end

  # Independent signal: even if modification rate is low, a high exclusion
  # rate means the user actively rejects rows. auto-post would still ship
  # unwanted rows to the ledger.
  #
  # Denominator: all non-deleted session transactions (including rolled_back).
  # Excluded rows are rolled_back and therefore drop out of `reviewable`, so
  # using the reviewable scope would understate the candidate pool.
  def exclusion_rate
    return "## Row exclusion rate\n  (no committed sessions in scope)" if committed_ids.empty?

    candidate_per_session = Transaction
                              .where(parsing_session_id: committed_ids, deleted: false)
                              .group(:parsing_session_id)
                              .count

    excluded_per_session = ImportReviewEvent
                             .where(parsing_session_id: committed_ids, event_type: "transaction_excluded")
                             .where.not(reviewed_transaction_id: nil)
                             .distinct
                             .group(:parsing_session_id)
                             .count(:reviewed_transaction_id)

    rates = committed_ids.filter_map do |sid|
      total = candidate_per_session[sid] || 0
      next nil if total.zero?
      (excluded_per_session[sid] || 0).to_f / total
    end

    return "## Row exclusion rate\n  (no candidate transactions in committed sessions)" if rates.empty?

    format_rate_section(
      title: "Row exclusion rate (distinct excluded transaction / candidate)",
      label: "exclusion",
      rates: rates,
      footer: "수정률이 낮아도 제외율이 높으면 auto-post 전환 시 잘못된 row가 자동으로 장부에 들어갈 수 있음."
    )
  end

  def import_issue_distribution
    rows = ImportIssue
             .where(parsing_session_id: @session_ids)
             .group(:source_type, :issue_type, :status)
             .count
    if rows.empty?
      return "## ImportIssue distribution\n  (no issues in scope)"
    end

    lines = [ "## ImportIssue distribution (source × type × status)" ]
    rows.sort_by { |k, _| k }.each do |(source, type, status), n|
      lines << "  #{source.ljust(13)} #{type.ljust(25)} #{status.ljust(10)} #{n.to_s.rjust(5)}"
    end
    lines.join("\n")
  end

  def commit_latency
    pairs = ParsingSession
              .where(id: @session_ids, review_status: "committed")
              .where.not(completed_at: nil, committed_at: nil)
              .pluck(:completed_at, :committed_at)

    deltas = pairs.map { |c, k| k - c }.reject(&:negative?)
    return "## Commit latency\n  (no committed sessions with timestamps)" if deltas.empty?

    avg = deltas.sum / deltas.size
    sorted = deltas.sort

    [
      "## Commit latency (completed_at → committed_at)",
      "  sessions analyzed: #{deltas.size}",
      "  average: #{humanize_duration(avg)}",
      "  p50:     #{humanize_duration(percentile(sorted, 0.5))}",
      "  p90:     #{humanize_duration(percentile(sorted, 0.9))}"
    ].join("\n")
  end

  def committed_ids
    @committed_ids ||= ParsingSession.where(id: @session_ids, review_status: "committed").pluck(:id)
  end

  def reviewable_count_per_session
    Transaction.reviewable.where(parsing_session_id: committed_ids).group(:parsing_session_id).count
  end

  def reviewable_transaction_ids
    Transaction.reviewable.where(parsing_session_id: committed_ids).pluck(:id)
  end

  def format_rate_section(title:, label:, rates:, footer:)
    avg = rates.sum / rates.size
    distribution = bucket(rates)
    lines = [ "## #{title}" ]
    lines << "  committed sessions analyzed: #{rates.size}"
    lines << "  average #{label} rate: #{(avg * 100).round(1)}%"
    lines << "  distribution:"
    distribution.each { |bucket_label, count| lines << "    #{bucket_label.ljust(12)} #{count}" }
    lines << "  #{footer}"
    lines.join("\n")
  end

  def bucket(rates)
    buckets = { "<10%" => 0, "10–30%" => 0, ">30%" => 0 }
    rates.each do |r|
      pct = r * 100
      if pct < 10 then buckets["<10%"] += 1
      elsif pct <= 30 then buckets["10–30%"] += 1
      else buckets[">30%"] += 1
      end
    end
    buckets
  end

  # Nearest-rank percentile on a 0-indexed sorted array. For n=10, p=0.9 →
  # idx = (9 * 0.9).round = 8 → sorted[8] (9th value). Avoids the off-by-one
  # of `(n * p).floor` which picks sorted[9] (= max) when n*p is an integer.
  def percentile(sorted, p)
    return nil if sorted.empty?
    return sorted.first if sorted.size == 1

    idx = ((sorted.size - 1) * p).round
    idx = sorted.size - 1 if idx > sorted.size - 1
    sorted[idx]
  end

  def humanize_duration(seconds)
    return "(unknown)" if seconds.nil?
    s = seconds.to_i
    if s < 60 then "#{s}s"
    elsif s < 3600 then "#{(s / 60.0).round(1)}m"
    elsif s < 86_400 then "#{(s / 3600.0).round(1)}h"
    else "#{(s / 86_400.0).round(1)}d"
    end
  end
end
