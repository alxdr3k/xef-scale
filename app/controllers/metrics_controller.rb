# Phase 7-1: web admin metrics dashboard (Issue #187 baseline web view).
#
# `ImportReviewMetricsReport` CLI service를 workspace admin이 web에서 볼 수 있게
# 노출. 출력 자체는 그대로 텍스트 포맷 — Phase 7-2+에서 HTML 차트로 확장 예정.
#
# Authorization:
#   - workspace 관리자(admin)만 접근. read-only 멤버도 차단.
class MetricsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :require_workspace_admin_access

  def show
    @since, since_invalid = parse_date_with_status(params[:since])
    @until, until_invalid = parse_date_with_status(params[:until])
    # form 에 사용자가 입력한 raw 값을 그대로 재표시해, 무엇이 잘못된 입력인지 보이게 한다.
    @raw_since = params[:since]
    @raw_until = params[:until]

    # invalid 입력을 silent widening 하지 않는다. 잘못된 날짜를 nil로 떨어뜨려
    # 전체 범위로 보여주면 admin이 분석 결과를 잘못 해석할 수 있다.
    invalid_fields = []
    invalid_fields << "since" if since_invalid
    invalid_fields << "until" if until_invalid
    if @since && @until && @since > @until
      invalid_fields << "range_order"
    end
    @metrics_invalid = invalid_fields.any?

    respond_to do |format|
      format.html do
        # HTML 도 invalid 일 때 report sections/export link 를 렌더하지 않는다.
        # flash alert 만 띄우고 widened/empty dataset 을 그대로 보여 주면
        # admin 이 잘못된 데이터를 실제 분석 결과로 읽을 수 있다 (CSV 422 거부와 동일 정책).
        if @metrics_invalid
          flash.now[:alert] = t("metrics.show.invalid_date_filter", fields: invalid_fields.join(", "))
          @sections = []
          @session_count = 0
          render :show, status: :unprocessable_entity
        else
          sessions = scoped_sessions
          @session_count = sessions.count
          @sections = report_for(sessions).sections
        end
      end
      format.csv do
        # CSV 다운로드에서는 flash가 노출되지 않는다 — invalid 입력이면 silent
        # range widening 대신 422로 명시적으로 거부. 분석 자동화가 잘못된 dataset을
        # downstream에 흘리지 않게.
        if @metrics_invalid
          render plain: t("metrics.show.invalid_date_filter", fields: invalid_fields.join(", ")),
                 status: :unprocessable_entity,
                 content_type: "text/plain; charset=utf-8"
        else
          sessions = scoped_sessions
          send_data csv_for(report_for(sessions).sections),
                    filename: csv_filename,
                    type: "text/csv; charset=utf-8"
        end
      end
    end
  end

  private

  def scoped_sessions
    sessions = @workspace.parsing_sessions
    sessions = sessions.where("created_at >= ?", @since) if @since
    sessions = sessions.where("created_at < ?", @until) if @until
    sessions
  end

  def report_for(sessions)
    ImportReviewMetricsReport.new(
      sessions: sessions,
      options: { workspace_id: @workspace.id, since: @since, until: @until }
    )
  end

  # set_workspace 는 ApplicationController의 메서드를 그대로 사용 (Codex PR #236 P2):
  # ActiveRecord::RecordNotFound rescue + workspaces_path redirect + 한국어 alert
  # 흐름이 다른 workspace-scoped controllers 와 일치하도록.

  # 엄격한 YYYY-MM-DD만 수용. Date.strptime은 trailing garbage("2026-01-01abc")와
  # 0-padding 없는 형식("2026-1-1")을 silently 받아들이므로, 사전에 정확 길이/숫자
  # 규격을 검증해야 admin이 입력 형식을 일관되게 인식한다.
  # blank → [nil, false], 잘못된 형식 → [nil, true].
  STRICT_DATE_RE = /\A\d{4}-\d{2}-\d{2}\z/

  def parse_date_with_status(raw)
    return [ nil, false ] if raw.blank?
    return [ nil, true ] unless STRICT_DATE_RE.match?(raw.to_s)
    [ Date.strptime(raw.to_s, "%Y-%m-%d"), false ]
  rescue ArgumentError
    [ nil, true ]
  end

  # Schema version 이 1을 넘어가는 변경 (column 추가/제거/key 의미 변경) 은 외부
  # 소비자에게 알리기 위해 명시적으로 bump 한다.
  CSV_SCHEMA_VERSION = 1

  # Phase 7-4: 외부 분석 도구로 메트릭 데이터를 가져갈 수 있도록 CSV export.
  # sections 데이터를 long-format (section,metric,value) 로 flatten — 한 줄당 한 값.
  # Excel/스프레드시트에서 pivot 하기 좋은 형태.
  #
  # `meta` 섹션이 가장 먼저 나온다: schema_version, workspace_id, range_start,
  # range_end (inclusive lower bound · exclusive upper bound), generated_at_utc.
  # 외부 소비자가 dataset 신뢰성·범위·schema 호환성을 자동 검사할 수 있도록.
  def csv_for(sections)
    require "csv"
    CSV.generate(headers: true) do |csv|
      csv << %w[section metric value]
      csv << [ "meta", "schema_version", CSV_SCHEMA_VERSION ]
      csv << [ "meta", "workspace_id", @workspace.id ]
      csv << [ "meta", "range_start", @since&.iso8601 ] # inclusive (created_at >=)
      csv << [ "meta", "range_end", @until&.iso8601 ]   # exclusive (created_at <)
      csv << [ "meta", "range_semantics", "start_inclusive_end_exclusive" ]
      csv << [ "meta", "generated_at_utc", Time.current.utc.iso8601 ]
      sections.each do |s|
        case s[:type]
        when :header
          csv << [ "header", "generated_at", s[:generated_at] ]
          csv << [ "header", "scope", s[:scope_summary] ]
          csv << [ "header", "session_count", s[:session_count] ]
        when :status_distribution
          csv << [ "status_distribution", "total", s[:total] ]
          s[:rows].each do |row|
            key = "#{row[:status]}/#{row[:review_status]}"
            csv << [ "status_distribution", "#{key}.count", row[:count] ]
            csv << [ "status_distribution", "#{key}.pct", row[:pct] ]
          end
        when :rate
          prefix = s[:key].to_s
          # `state` 를 먼저 내보내, 외부 분석 도구가 avg_pct blank 의 원인을
          # `no_committed` (운영 데이터 부재) vs `no_data` (분모 0) vs `ok` 로 구분할 수 있게 한다.
          csv << [ prefix, "state", s[:state] ]
          csv << [ prefix, "sessions_analyzed", s[:sessions_analyzed] ]
          csv << [ prefix, "avg_pct", s[:avg_pct] ]
          (s[:distribution] || {}).each { |bucket, n| csv << [ prefix, "bucket.#{bucket}", n ] }
        when :classification_source_distribution
          csv << [ "classification_source", "total", s[:total] ]
          csv << [ "classification_source", "gemini_final_share_pct", s[:gemini_final_share_pct] ]
          s[:rows].each do |row|
            key = row[:source] || "(none)"
            csv << [ "classification_source", "#{key}.count", row[:count] ]
            csv << [ "classification_source", "#{key}.pct", row[:pct] ]
          end
        when :import_issues
          s[:rows].each do |row|
            key = "#{row[:source_type]}/#{row[:issue_type]}/#{row[:status]}"
            csv << [ "import_issues", "#{key}.count", row[:count] ]
          end
        when :commit_latency
          csv << [ "commit_latency", "sessions_analyzed", s[:sessions_analyzed] ]
          csv << [ "commit_latency", "average_seconds", s[:average_seconds] ]
          csv << [ "commit_latency", "p50_seconds", s[:p50_seconds] ]
          csv << [ "commit_latency", "p90_seconds", s[:p90_seconds] ]
        end
      end
    end
  end

  def csv_filename
    parts = [ "metrics", @workspace.id ]
    parts << "since-#{@since}" if @since
    parts << "until-#{@until}" if @until
    parts << Time.current.strftime("%Y%m%d-%H%M%S")
    "#{parts.join('_')}.csv"
  end
end
