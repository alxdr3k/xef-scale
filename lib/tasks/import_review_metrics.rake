# Import review metrics for Issue #187 (auto-post 결정 데이터)
#
# PR #189에서 도입한 ImportReviewEvent + ImportIssue + ParsingSession 상태로
# 다음 지표를 산출한다:
#   1. session별 distinct transaction 기준 row 수정 비율 (수정 비율 — Issue #187 핵심)
#   2. session 종료 분포 (committed / rolled_back / discarded)
#   3. ImportIssue 분포 (open / resolved / dismissed by source_type)
#   4. completed → committed latency (review에서 commit까지 걸린 시간)
#
# 사용:
#   bin/rails import_review_metrics:report
#   bin/rails 'import_review_metrics:report[--workspace=5 --since=2026-05-17]'
#
# 인자(괄호 안):
#   --workspace=ID      특정 workspace로 필터 (생략 시 전체)
#   --since=YYYY-MM-DD  parsing_session.created_at 기준 시작일
#   --until=YYYY-MM-DD  parsing_session.created_at 기준 종료일 (배타적)
#
# 출력은 사람이 읽는 텍스트. CI/스크립트 연결이 필요하면 후속 PR에서 --json
# 옵션을 추가한다.

namespace :import_review_metrics do
  desc "Issue #187 baseline: import review behavior summary"
  task :report, [ :args ] => :environment do |_t, args|
    options = ImportReviewMetricsCli.parse(args[:args].to_s)

    sessions = ParsingSession.all
    sessions = sessions.where(workspace_id: options[:workspace_id]) if options[:workspace_id]
    sessions = sessions.where("created_at >= ?", options[:since]) if options[:since]
    sessions = sessions.where("created_at < ?", options[:until]) if options[:until]

    puts ImportReviewMetricsReport.new(sessions: sessions, options: options).render
  end
end

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
        out[:since] = Date.parse($1)
      when /\A--until=(\d{4}-\d{2}-\d{2})\z/
        out[:until] = Date.parse($1)
      end
    end
    out
  end
end

class ImportReviewMetricsReport
  def initialize(sessions:, options:)
    @sessions = sessions
    @session_ids = @sessions.pluck(:id)
    @options = options
  end

  def render
    lines = []
    lines << header
    lines << termination_distribution
    lines << modification_rate
    lines << import_issue_distribution
    lines << commit_latency
    lines.join("\n\n")
  end

  private

  def header
    parts = [ "# Import Review Metrics (Issue #187 baseline)" ]
    parts << "Generated: #{Time.current.iso8601}"
    parts << "Scope: #{scope_summary}"
    parts << "Sessions in scope: #{@session_ids.size}"
    parts.join("\n")
  end

  def scope_summary
    bits = []
    bits << (@options[:workspace_id] ? "workspace=#{@options[:workspace_id]}" : "all workspaces")
    bits << "since=#{@options[:since]}" if @options[:since]
    bits << "until=#{@options[:until]}" if @options[:until]
    bits.join(", ")
  end

  def termination_distribution
    counts = ParsingSession.where(id: @session_ids).group(:review_status).count
    total = counts.values.sum
    rows = ParsingSession::REVIEW_STATUSES.map do |status|
      n = counts[status] || 0
      pct = total.positive? ? (100.0 * n / total).round(1) : 0.0
      "  #{status.ljust(15)} #{n.to_s.rjust(6)}  (#{pct}%)"
    end
    "## Session termination distribution\n" + rows.join("\n")
  end

  def modification_rate
    # distinct reviewed_transaction_id per session — Issue #187 결정 기준.
    # 같은 row를 여러 번 수정해도 1로 집계.
    committed_sessions = ParsingSession.where(id: @session_ids, review_status: "committed")
    committed_ids = committed_sessions.pluck(:id)
    return "## Row modification rate\n  (no committed sessions in scope)" if committed_ids.empty?

    modified_per_session = ImportReviewEvent
                             .where(parsing_session_id: committed_ids, event_type: "transaction_updated")
                             .where.not(reviewed_transaction_id: nil)
                             .distinct
                             .group(:parsing_session_id)
                             .count(:reviewed_transaction_id)

    reviewable_per_session = Transaction
                               .where(parsing_session_id: committed_ids, deleted: false)
                               .group(:parsing_session_id)
                               .count

    rates = committed_ids.filter_map do |sid|
      total = reviewable_per_session[sid] || 0
      next nil if total.zero?
      mod = modified_per_session[sid] || 0
      mod.to_f / total
    end

    return "## Row modification rate\n  (no reviewable transactions in committed sessions)" if rates.empty?

    avg = rates.sum / rates.size
    distribution = bucket(rates)
    lines = [ "## Row modification rate (distinct transaction / reviewable)" ]
    lines << "  committed sessions analyzed: #{rates.size}"
    lines << "  average modification rate: #{(avg * 100).round(1)}%"
    lines << "  distribution:"
    distribution.each { |label, count| lines << "    #{label.ljust(12)} #{count}" }
    lines << "  Issue #187 thresholds: <10% = C(auto-post) 후보 / 10–30% = B 유지 / >30% = A 강화"
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
    sessions = ParsingSession
                 .where(id: @session_ids, review_status: "committed")
                 .where.not(completed_at: nil, committed_at: nil)
                 .pluck(:completed_at, :committed_at)

    deltas = sessions.map { |c, k| k - c }.reject(&:negative?)
    return "## Commit latency\n  (no committed sessions with timestamps)" if deltas.empty?

    avg = deltas.sum / deltas.size
    sorted = deltas.sort
    p50 = sorted[(sorted.size * 0.5).floor]
    p90 = sorted[[ (sorted.size * 0.9).floor, sorted.size - 1 ].min]

    [
      "## Commit latency (completed_at → committed_at)",
      "  sessions analyzed: #{deltas.size}",
      "  average: #{humanize_duration(avg)}",
      "  p50:     #{humanize_duration(p50)}",
      "  p90:     #{humanize_duration(p90)}"
    ].join("\n")
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
