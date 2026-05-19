class ImportReviewMetricsReport
  def initialize(sessions:, options:)
    @sessions = sessions
    @session_ids = @sessions.pluck(:id)
    @options = options
  end

  # text render와 HTML/CSV view는 모두 `sections` Hash 배열을 단일 소스로 본다.
  # render는 sections 결과를 text로 포매팅만 한다 — drift 차단.
  def render
    sections.map { |s| text_for(s) }.join("\n\n")
  end

  # 구조화 데이터 source (HTML 카드, CSV export, text render 공용).
  def sections
    @sections ||= [
      header_section,
      status_distribution_section,
      rate_section(:modification),
      rate_section(:exclusion),
      classification_source_distribution_section,
      import_issue_distribution_section,
      commit_latency_section
    ]
  end

  def header_section
    {
      type: :header,
      generated_at: Time.current.iso8601,
      scope_summary: scope_summary,
      session_count: @session_ids.size
    }
  end

  def status_distribution_section
    rows = ParsingSession
             .where(id: @session_ids)
             .group(:status, :review_status)
             .count
    total = rows.values.sum
    formatted = rows.sort_by { |(status, review_status), _| [ status.to_s, review_status.to_s ] }
                    .map { |(status, review_status), n|
                      pct = total.zero? ? 0.0 : (100.0 * n / total).round(1)
                      { status: status.to_s, review_status: review_status.to_s, count: n, pct: pct }
                    }
    { type: :status_distribution, total: total, rows: formatted }
  end

  # rate_section: state 필드로 empty-state 분기를 캐리한다. text/HTML/CSV 어디서든
  # "왜 비었는가"를 같은 source에서 읽어 drift를 막는다.
  #   :no_committed  — committed session 없음
  #   :no_data       — committed 있으나 분모(reviewable/candidate) 없음
  #   :ok            — 정상 데이터
  def rate_section(kind)
    if committed_ids.empty?
      return {
        type: :rate, key: kind, state: :no_committed,
        rates: [], avg_pct: nil, distribution: nil, sessions_analyzed: 0
      }
    end
    rates = kind == :modification ? modification_rates : exclusion_rates
    state = rates.empty? ? :no_data : :ok
    {
      type: :rate,
      key: kind,
      state: state,
      rates: rates,
      avg_pct: rates.any? ? (rates.sum / rates.size * 100).round(1) : nil,
      distribution: rates.any? ? bucket(rates) : nil,
      sessions_analyzed: rates.size
    }
  end

  def import_issue_distribution_section
    rows = ImportIssue
             .where(parsing_session_id: @session_ids)
             .group(:source_type, :issue_type, :status)
             .count
    formatted = rows.sort_by { |(source, type, status), _| [ source.to_s, type.to_s, status.to_s ] }
                    .map { |(source, type, status), n|
                      { source_type: source.to_s, issue_type: type.to_s, status: status.to_s, count: n }
                    }
    { type: :import_issues, rows: formatted }
  end

  # Phase 7-3: classification_source 분포 — 4 분류 메커니즘 비율 + Gemini 최종 분류 비율.
  #
  # `gemini_final_share_pct`는 committed reviewable 거래 중 최종 classification_source가
  # `gemini_batch`로 남아 있는 비율이다. "AI 수용률"이 아니다. 이유:
  #   - 사용자가 AI 추천을 *보고 수락*했다는 이벤트를 추적하지 않는다.
  #   - Gemini가 만든 mapping (FileParsingJob#categorize_with_gemini_batch에서
  #     CategoryMapping.find_or_create_by!)은 후속 거래를 `mapping_match`로 잡으므로
  #     AI 학습 효과가 metric에서 빠진다.
  # 정확한 수용률은 추천 시점 vs commit 시점 snapshot 비교가 필요하다 (별도 슬라이스).
  #
  # 분모는 committed sessions의 reviewable transaction 중 classification_source 가 *set 된* 거래.
  # nil/blank source 는 분류되지 않은 거래 (예: 직접 입력 후 카테고리 미선택) 로 별도 집계.
  def classification_source_distribution_section
    counts = Transaction.reviewable
                        .where(parsing_session_id: committed_ids)
                        .group(:classification_source)
                        .count
    total = counts.values.sum
    # 정렬: 비율 의미 순서. ADR-0007 §1.1 (1→2→3→manual).
    keys = %w[mapping_match keyword_match gemini_batch manual_set]
    rows = keys.map do |key|
      n = counts[key].to_i
      pct = total.zero? ? 0.0 : (100.0 * n / total).round(1)
      { source: key, count: n, pct: pct }
    end
    nil_count = counts[nil].to_i
    if nil_count.positive?
      pct = total.zero? ? 0.0 : (100.0 * nil_count / total).round(1)
      rows << { source: nil, count: nil_count, pct: pct }
    end

    gemini_count = counts["gemini_batch"].to_i
    gemini_final_share_pct = total.zero? ? nil : (100.0 * gemini_count / total).round(1)

    {
      type: :classification_source_distribution,
      total: total,
      rows: rows,
      gemini_final_share_pct: gemini_final_share_pct
    }
  end

  def commit_latency_section
    pairs = ParsingSession
              .where(id: @session_ids, review_status: "committed")
              .where.not(completed_at: nil, committed_at: nil)
              .pluck(:completed_at, :committed_at)

    deltas = pairs.map { |c, k| k - c }.reject(&:negative?)
    if deltas.empty?
      return { type: :commit_latency, sessions_analyzed: 0 }
    end

    sorted = deltas.sort
    avg = deltas.sum / deltas.size
    {
      type: :commit_latency,
      sessions_analyzed: deltas.size,
      average_seconds: avg.to_i,
      p50_seconds: percentile(sorted, 0.5).to_i,
      p90_seconds: percentile(sorted, 0.9).to_i,
      average_humanized: humanize_duration(avg),
      p50_humanized: humanize_duration(percentile(sorted, 0.5)),
      p90_humanized: humanize_duration(percentile(sorted, 0.9))
    }
  end

  private

  # Text formatter dispatcher. 새 섹션 type을 추가할 때 여기 한 곳만 확장하면 된다.
  def text_for(section)
    case section[:type]
    when :header                            then header_text(section)
    when :status_distribution               then status_distribution_text(section)
    when :rate                              then rate_text(section)
    when :classification_source_distribution then classification_source_distribution_text(section)
    when :import_issues                     then import_issue_distribution_text(section)
    when :commit_latency                    then commit_latency_text(section)
    end
  end

  def header_text(section)
    [
      "# Import Review Metrics (Issue #187 baseline)",
      "Generated: #{section[:generated_at]}",
      "Scope: #{section[:scope_summary]}",
      "Sessions in scope: #{section[:session_count]}"
    ].join("\n")
  end

  def status_distribution_text(section)
    return "## Session status distribution\n  (no sessions in scope)" if section[:total].zero?

    lines = [ "## Session status distribution (status × review_status)" ]
    section[:rows].each do |row|
      status_label = row[:status].presence || "(nil)"
      review_label = row[:review_status].presence || "(nil)"
      label = "#{status_label} / #{review_label}".ljust(32)
      lines << "  #{label} #{row[:count].to_s.rjust(6)}  (#{row[:pct]}%)"
    end
    lines.join("\n")
  end

  RATE_TEXT_META = {
    modification: {
      title: "Row modification rate (distinct transaction / reviewable)",
      label: "modification",
      no_data_msg: "(no reviewable transactions in committed sessions)",
      footer: "Issue #187 thresholds: <10% = C(auto-post) 후보 / 10–30% = B 유지 / >30% = A 강화"
    },
    exclusion: {
      title: "Row exclusion rate (distinct excluded transaction / candidate)",
      label: "exclusion",
      no_data_msg: "(no candidate transactions in committed sessions)",
      footer: "수정률이 낮아도 제외율이 높으면 auto-post 전환 시 잘못된 row가 자동으로 장부에 들어갈 수 있음."
    }
  }.freeze

  def rate_text(section)
    meta = RATE_TEXT_META.fetch(section[:key])
    short_title = meta[:title].split(" (").first
    case section[:state]
    when :no_committed
      "## #{short_title}\n  (no committed sessions in scope)"
    when :no_data
      "## #{short_title}\n  #{meta[:no_data_msg]}"
    else
      avg_str = "%.1f" % section[:avg_pct]
      lines = [ "## #{meta[:title]}" ]
      lines << "  committed sessions analyzed: #{section[:sessions_analyzed]}"
      lines << "  average #{meta[:label]} rate: #{avg_str}%"
      lines << "  distribution:"
      section[:distribution].each { |bucket_label, count| lines << "    #{bucket_label.ljust(12)} #{count}" }
      lines << "  #{meta[:footer]}"
      lines.join("\n")
    end
  end

  def classification_source_distribution_text(section)
    return "## Classification source distribution\n  (no committed reviewable transactions)" if section[:total].zero?

    lines = [ "## Classification source distribution" ]
    lines << "  total reviewable transactions: #{section[:total]}"
    section[:rows].each do |row|
      label = (row[:source] || "(none)").ljust(16)
      lines << "  #{label} #{row[:count].to_s.rjust(6)}  (#{row[:pct]}%)"
    end
    if section[:gemini_final_share_pct]
      lines << "  Gemini final share (gemini_batch / total): #{section[:gemini_final_share_pct]}%"
      lines << "  최종 classification_source가 gemini_batch인 비율 — 수용률 아님. Gemini가 만든 mapping은 후속 거래에서 mapping_match로 집계됨."
    end
    lines.join("\n")
  end

  def import_issue_distribution_text(section)
    return "## ImportIssue distribution\n  (no issues in scope)" if section[:rows].empty?

    lines = [ "## ImportIssue distribution (source × type × status)" ]
    section[:rows].each do |row|
      lines << "  #{row[:source_type].ljust(13)} #{row[:issue_type].ljust(25)} #{row[:status].ljust(10)} #{row[:count].to_s.rjust(5)}"
    end
    lines.join("\n")
  end

  def commit_latency_text(section)
    return "## Commit latency\n  (no committed sessions with timestamps)" if section[:sessions_analyzed].zero?

    [
      "## Commit latency (completed_at → committed_at)",
      "  sessions analyzed: #{section[:sessions_analyzed]}",
      "  average: #{section[:average_humanized]}",
      "  p50:     #{section[:p50_humanized]}",
      "  p90:     #{section[:p90_humanized]}"
    ].join("\n")
  end

  def scope_summary
    bits = []
    bits << (@options[:workspace_id] ? "workspace=#{@options[:workspace_id]}" : "all workspaces")
    bits << "since=#{@options[:since]}" if @options[:since]
    bits << "until=#{@options[:until]}" if @options[:until]
    bits.join(", ")
  end

  def modification_rates
    return [] if committed_ids.empty?

    reviewable_per_session = reviewable_count_per_session
    reviewable_tx_ids = reviewable_transaction_ids

    modified_per_session = ImportReviewEvent
                             .where(parsing_session_id: committed_ids, event_type: "transaction_updated")
                             .where(reviewed_transaction_id: reviewable_tx_ids)
                             .distinct
                             .group(:parsing_session_id)
                             .count(:reviewed_transaction_id)

    committed_ids.filter_map do |sid|
      total = reviewable_per_session[sid] || 0
      next nil if total.zero?
      (modified_per_session[sid] || 0).to_f / total
    end
  end

  def exclusion_rates
    return [] if committed_ids.empty?

    # Read excluded rows from authoritative Transaction state (status: rolled_back)
    # instead of the transaction_excluded event log. This captures every
    # exclusion path — including duplicate decisions that flip a row to
    # rolled_back without emitting an event (ParsingSession#apply_duplicate_decisions!
    # for keep_original / keep_neither) — and is stable against later edits
    # because rolled_back rows do not get soft-deleted.
    #
    # Denominator covers every row the session ever created (including later
    # soft-deletes via TransactionsController#destroy), so the rate does not
    # drift up retroactively as users prune the ledger.
    candidate_per_session = Transaction
                              .unscoped
                              .where(parsing_session_id: committed_ids)
                              .group(:parsing_session_id)
                              .count

    excluded_per_session = Transaction
                             .unscoped
                             .where(parsing_session_id: committed_ids, status: "rolled_back")
                             .group(:parsing_session_id)
                             .count

    committed_ids.filter_map do |sid|
      total = candidate_per_session[sid] || 0
      next nil if total.zero?
      (excluded_per_session[sid] || 0).to_f / total
    end
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

  # Standard nearest-rank percentile (1-indexed: rank = ceil(p * n)), then
  # converted to a 0-indexed array index. For n=10, p=0.9 → ceil(9) = 9 →
  # sorted[8]. For n=2, p=0.5 → ceil(1) = 1 → sorted[0] (lower median), which
  # `round`-based indexing would have biased to the max.
  def percentile(sorted, p)
    return nil if sorted.empty?
    return sorted.first if sorted.size == 1

    rank = (sorted.size * p).ceil
    rank = 1 if rank < 1
    rank = sorted.size if rank > sorted.size
    sorted[rank - 1]
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
