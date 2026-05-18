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
    @since = parse_date(params[:since])
    @until = parse_date(params[:until])

    sessions = @workspace.parsing_sessions
    sessions = sessions.where("created_at >= ?", @since) if @since
    sessions = sessions.where("created_at < ?", @until) if @until

    options = { workspace_id: @workspace.id, since: @since, until: @until }
    @report = ImportReviewMetricsReport.new(sessions: sessions, options: options).render
    @session_count = sessions.count
  end

  private

  def set_workspace
    @workspace = current_user.workspaces.find(params[:workspace_id])
  end

  # YYYY-MM-DD 만 수용. 잘못된 형식은 nil로 무시 (사용자 입력 신뢰 안 함).
  def parse_date(raw)
    return nil if raw.blank?
    Date.strptime(raw.to_s, "%Y-%m-%d")
  rescue ArgumentError
    nil
  end
end
