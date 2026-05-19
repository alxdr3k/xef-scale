require "test_helper"

class MetricsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
    @member = users(:member)
    @workspace = workspaces(:main_workspace)
  end

  test "show requires authentication" do
    get workspace_metrics_path(@workspace)
    assert_redirected_to new_user_session_path
  end

  test "show requires workspace admin access (member_read rejected)" do
    sign_in @member
    get workspace_metrics_path(@workspace)
    # require_workspace_admin_access redirects non-admin to workspaces_path.
    assert_response :redirect
  end

  test "show renders metrics report for admin" do
    sign_in @admin
    get workspace_metrics_path(@workspace)
    assert_response :success
    assert_select "h1", text: /검토 메트릭/
    # Phase 7-2: HTML 카드 — 각 섹션 partial이 렌더되었는지 확인.
    assert_select "h2", text: /요약/
    assert_select "h2", text: /세션 상태 분포/
  end

  test "show accepts valid since/until filters" do
    sign_in @admin
    get workspace_metrics_path(@workspace, since: "2026-01-01", until: "2026-05-18")
    assert_response :success
    # 유효 범위면 alert 없음
    assert_select ".flash-alert, [data-flash='alert']", false
  end

  test "show surfaces invalid date filter as flash alert (no silent widening)" do
    sign_in @admin
    get workspace_metrics_path(@workspace, since: "not-a-date", until: "also-bad")
    assert_response :success
    # admin이 분석 결과를 잘못 해석하지 않도록 invalid 입력은 alert로 노출.
    assert_match(/날짜 필터가 올바르지 않습니다/, @response.body)
    assert_match(/since/, @response.body)
    assert_match(/until/, @response.body)
  end

  test "show flags since > until as invalid" do
    sign_in @admin
    get workspace_metrics_path(@workspace, since: "2026-05-18", until: "2026-01-01")
    assert_response :success
    assert_match(/날짜 필터가 올바르지 않습니다/, @response.body)
    assert_match(/range_order/, @response.body)
  end

  # Codex PR #236 P2: ApplicationController#set_workspace 와 동일한 RecordNotFound
  # rescue 흐름을 metrics에서도 강제 — invalid id 에 대해 404 예외 path 가 아니라
  # workspaces_path 로 redirect.
  test "show with non-member workspace id redirects to workspaces (no 404)" do
    sign_in @admin
    other = workspaces(:other_workspace) # admin은 other_workspace 멤버 아님
    get workspace_metrics_path(other)
    assert_response :redirect
    assert_redirected_to workspaces_path
  end

  # Phase 7-4: CSV export (외부 분석 도구 호환).
  test "show.csv returns CSV with section/metric/value headers" do
    sign_in @admin
    get workspace_metrics_path(@workspace, format: :csv)
    assert_response :success
    assert_match %r{text/csv}, @response.content_type
    body = @response.body
    assert_match(/\Asection,metric,value\n/, body)
    # 핵심 섹션 명 포함 검사 — 빈 데이터라도 header / classification_source / commit_latency 등 노출.
    assert_includes body, "header,scope"
    assert_includes body, "header,session_count"
  end

  # CSV schema 안정성: 외부 분석 도구가 신뢰할 수 있도록 meta block을 가장 먼저
  # 노출. schema_version bump 없이 의미가 바뀌지 않는다는 contract.
  test "show.csv includes meta block with schema_version and range" do
    sign_in @admin
    get workspace_metrics_path(@workspace, format: :csv, since: "2026-01-01", until: "2026-05-18")
    body = @response.body
    assert_match(/\Asection,metric,value\nmeta,schema_version,1\n/, body)
    assert_includes body, "meta,workspace_id,#{@workspace.id}"
    assert_includes body, "meta,range_start,2026-01-01"
    assert_includes body, "meta,range_end,2026-05-18"
    assert_includes body, "meta,range_semantics,start_inclusive_end_exclusive"
    assert_match(/meta,generated_at_utc,\d{4}-\d{2}-\d{2}T/, body)
  end

  test "show.csv meta block leaves range blank when no filters set" do
    sign_in @admin
    get workspace_metrics_path(@workspace, format: :csv)
    body = @response.body
    # blank range는 빈 값으로 표시 — 자동화에서 nil 처리 일관성.
    assert_match(/meta,range_start,\n/, body)
    assert_match(/meta,range_end,\n/, body)
  end

  test "show.csv filename includes workspace + range" do
    sign_in @admin
    get workspace_metrics_path(@workspace, format: :csv, since: "2026-01-01", until: "2026-05-18")
    disposition = @response.headers["Content-Disposition"]
    assert_match(/metrics_#{@workspace.id}_since-2026-01-01_until-2026-05-18/, disposition)
    assert_match(/\.csv/, disposition)
  end

  test "show.csv requires admin (member_read rejected)" do
    sign_in @member
    get workspace_metrics_path(@workspace, format: :csv)
    assert_response :redirect
  end
end
