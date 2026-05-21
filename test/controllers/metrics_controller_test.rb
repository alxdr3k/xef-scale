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

  test "show rejects invalid date filter with 422 (no widened/empty report rendered)" do
    sign_in @admin
    get workspace_metrics_path(@workspace, since: "not-a-date", until: "also-bad")
    # invalid 입력이면 HTML 도 widened/empty dataset 을 렌더하지 않는다 (CSV 422 거부와 동일 정책).
    # admin 이 잘못된 데이터를 실제 분석 결과로 읽지 않도록.
    assert_response :unprocessable_entity
    assert_match(/날짜 필터가 올바르지 않습니다/, @response.body)
    assert_match(/since/, @response.body)
    assert_match(/until/, @response.body)
    # report sections / export 링크는 렌더되지 않는다.
    assert_select "h2", text: /요약/, count: 0
    assert_select "a", text: /CSV 내보내기/, count: 0
    # 사용자가 입력한 raw 값이 form 에 그대로 재표시되어 무엇이 잘못됐는지 확인 가능.
    assert_select "input[name='since'][value='not-a-date']"
    assert_select "input[name='until'][value='also-bad']"
  end

  test "show flags since > until as invalid (422, no report)" do
    sign_in @admin
    get workspace_metrics_path(@workspace, since: "2026-05-18", until: "2026-01-01")
    assert_response :unprocessable_entity
    assert_match(/날짜 필터가 올바르지 않습니다/, @response.body)
    assert_match(/range_order/, @response.body)
    assert_select "h2", text: /요약/, count: 0
  end

  test "show rejects trailing garbage and non-padded date formats with 422 (strptime laxness guard)" do
    sign_in @admin
    # Date.strptime은 "2026-01-01abc"와 "2026-1-1"을 silently 받아들이므로 강한 사전 검증 필요.
    get workspace_metrics_path(@workspace, since: "2026-01-01abc")
    assert_response :unprocessable_entity
    assert_match(/날짜 필터가 올바르지 않습니다/, @response.body)
    assert_match(/since/, @response.body)

    get workspace_metrics_path(@workspace, since: "2026-1-1")
    assert_response :unprocessable_entity
    assert_match(/날짜 필터가 올바르지 않습니다/, @response.body)
    assert_match(/since/, @response.body)
  end

  test "show.csv rejects invalid date filters with 422 instead of silent widening" do
    sign_in @admin
    # CSV 다운로드는 flash가 안 보이므로 422로 명시적 거부 — 분석 자동화 안전성.
    get workspace_metrics_path(@workspace, format: :csv, since: "not-a-date")
    assert_response :unprocessable_entity
    assert_match(/날짜 필터가 올바르지 않습니다/, @response.body)
    refute_match %r{text/csv}, @response.content_type
  end

  test "show.csv rejects since > until with 422" do
    sign_in @admin
    get workspace_metrics_path(@workspace, format: :csv, since: "2026-05-18", until: "2026-01-01")
    assert_response :unprocessable_entity
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

  # Rate state 가 HTML/CSV 양쪽에 전달되어 "왜 비었는가" 가 drift 하지 않는지 검증
  # (PR #243 후속). committed 세션 자체가 없을 때와 분모가 0일 때를 분리한다.
  test "show renders state-specific empty rate message when no committed sessions" do
    sign_in @admin
    # admin 이 owner 인 빈 workspace — after_create 가 owner membership 을 자동 생성해 admin_of? 통과.
    blank = Workspace.create!(name: "empty-metrics-#{SecureRandom.hex(2)}", owner: @admin)
    get workspace_metrics_path(blank)
    assert_response :success
    # committed 세션 없음 → no_committed 메시지 (no_data 와 구분)
    assert_match(/범위 내 commit된 세션이 없습니다/, @response.body)
  end

  test "show.csv emits rate state row for external consumers" do
    sign_in @admin
    get workspace_metrics_path(@workspace, format: :csv)
    assert_response :success
    body = @response.body
    # state 가 avg_pct/sessions_analyzed 보다 먼저 나와, blank avg_pct 의 원인을
    # 외부 분석 도구가 구분할 수 있게 한다.
    assert_match(/modification,state,(no_committed|no_data|ok)/, body)
    assert_match(/exclusion,state,(no_committed|no_data|ok)/, body)
  end
end
