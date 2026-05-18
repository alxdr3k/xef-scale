require "test_helper"

# ImportReviewMetricsCli/Report은 app/services에 있어 Rails autoload로
# 바로 사용 가능. 별도 load 불필요.

class ImportReviewMetricsCliTest < ActiveSupport::TestCase
  test "parses workspace, since, until arguments" do
    options = ImportReviewMetricsCli.parse("--workspace=42 --since=2026-05-01 --until=2026-06-01")

    assert_equal 42, options[:workspace_id]
    assert_equal Date.new(2026, 5, 1), options[:since]
    assert_equal Date.new(2026, 6, 1), options[:until]
  end

  test "ignores malformed arguments" do
    options = ImportReviewMetricsCli.parse("--nonsense --workspace=abc --since=bad")

    assert_nil options[:workspace_id]
    assert_nil options[:since]
  end

  test "ignores syntactically valid but invalid calendar dates" do
    options = ImportReviewMetricsCli.parse("--since=2026-02-31 --until=2026-13-01")

    assert_nil options[:since]
    assert_nil options[:until]
  end

  test "empty input returns default options" do
    options = ImportReviewMetricsCli.parse("")
    assert_nil options[:workspace_id]
    assert_nil options[:since]
    assert_nil options[:until]
  end
end

class ImportReviewMetricsReportTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:main_workspace)
  end

  test "renders report sections even when scope is empty" do
    empty_scope = ParsingSession.where(id: -1)
    output = ImportReviewMetricsReport.new(sessions: empty_scope, options: {}).render

    assert_includes output, "Session status distribution"
    assert_includes output, "Row modification rate"
    assert_includes output, "Row exclusion rate"
    assert_includes output, "ImportIssue distribution"
    assert_includes output, "Commit latency"
    assert_includes output, "Sessions in scope: 0"
  end

  test "status distribution uses status x review_status grid" do
    @workspace.parsing_sessions.create!(source_type: "file_upload", status: "completed", review_status: "committed")
    @workspace.parsing_sessions.create!(source_type: "file_upload", status: "failed", review_status: "pending_review")

    report = ImportReviewMetricsReport.new(
      sessions: @workspace.parsing_sessions,
      options: { workspace_id: @workspace.id }
    ).render

    # failed session이 단순 "pending_review"로 오해되지 않도록
    assert_match(/completed \/ committed/, report)
    assert_match(/failed \/ pending_review/, report)
  end

  test "modification rate uses reviewable scope (excludes rolled_back rows)" do
    session = @workspace.parsing_sessions.create!(
      source_type: "file_upload", status: "completed",
      review_status: "committed",
      completed_at: 2.minutes.ago, committed_at: 1.minute.ago
    )
    keeper = @workspace.transactions.create!(date: Date.current, amount: 1, status: "committed", parsing_session: session)
    @workspace.transactions.create!(date: Date.current, amount: 2, status: "committed", parsing_session: session)
    @workspace.transactions.create!(date: Date.current, amount: 3, status: "rolled_back", parsing_session: session)

    @workspace.import_review_events.create!(
      parsing_session: session, reviewed_transaction: keeper,
      event_type: "transaction_updated", changed_fields: [ "merchant" ]
    )

    report = ImportReviewMetricsReport.new(
      sessions: @workspace.parsing_sessions.where(id: session.id),
      options: {}
    ).render

    assert_match(/average modification rate: 50\.0%/, report)
  end

  test "modification rate does not count updates on rolled_back rows" do
    session = @workspace.parsing_sessions.create!(
      source_type: "file_upload", status: "completed",
      review_status: "committed",
      completed_at: 2.minutes.ago, committed_at: 1.minute.ago
    )
    keeper = @workspace.transactions.create!(date: Date.current, amount: 1, status: "committed", parsing_session: session)
    excluded = @workspace.transactions.create!(date: Date.current, amount: 2, status: "rolled_back", parsing_session: session)

    @workspace.import_review_events.create!(
      parsing_session: session, reviewed_transaction: excluded,
      event_type: "transaction_updated", changed_fields: [ "category_id" ]
    )

    report = ImportReviewMetricsReport.new(
      sessions: @workspace.parsing_sessions.where(id: session.id),
      options: {}
    ).render

    assert_match(/average modification rate: 0\.0%/, report)
    # Phase 7-3: 섹션을 빈 줄로 분리한 뒤 modification rate 섹션 안에만 100% 가
    # 안 나오는지 검사. 이전 `/.../m` greedy 매치가 새 섹션의 100% 까지 도달하던
    # 회귀 방지.
    modification_section = report.split("\n\n").find { |s| s.include?("Row modification rate") }
    refute_match(/100\.0%/, modification_section)
    assert excluded.rolled_back?
    assert keeper.committed?
  end

  test "exclusion rate counts distinct transactions per committed session" do
    session = @workspace.parsing_sessions.create!(
      source_type: "file_upload", status: "completed",
      review_status: "committed",
      completed_at: 2.minutes.ago, committed_at: 1.minute.ago
    )
    keeper = @workspace.transactions.create!(date: Date.current, amount: 1, status: "committed", parsing_session: session)
    excluded = @workspace.transactions.create!(date: Date.current, amount: 2, status: "rolled_back", parsing_session: session)

    # 같은 row를 두 번 excluded 이벤트로 기록해도 1로 집계되어야 함.
    2.times do
      @workspace.import_review_events.create!(
        parsing_session: session, reviewed_transaction: excluded,
        event_type: "transaction_excluded", changed_fields: []
      )
    end

    report = ImportReviewMetricsReport.new(
      sessions: @workspace.parsing_sessions.where(id: session.id),
      options: {}
    ).render

    # 후보 2건 (keeper + excluded, deleted false), 제외된 distinct 1건 → 50%
    assert_match(/Row exclusion rate.*?average exclusion rate: 50\.0%/m, report)
    assert keeper.persisted?
  end

  test "commit latency percentiles use nearest-rank (avoids off-by-one)" do
    base = 1.hour.ago
    10.times do |i|
      delta = i + 1
      @workspace.parsing_sessions.create!(
        source_type: "file_upload", status: "completed",
        review_status: "committed",
        completed_at: base, committed_at: base + delta.seconds
      )
    end

    report = ImportReviewMetricsReport.new(
      sessions: @workspace.parsing_sessions,
      options: { workspace_id: @workspace.id }
    ).render

    # nearest-rank with ceil: n=10, p=0.9 → rank = ceil(9) = 9 → sorted[8] = 9s.
    # p=0.5 → rank = ceil(5) = 5 → sorted[4] = 5s (lower median).
    assert_match(/p90:\s+9s/, report)
    refute_match(/p90:\s+10s/, report)
    assert_match(/p50:\s+5s/, report)
  end

  test "percentile uses ceil-based nearest-rank for tiny samples" do
    # n=2, p=0.5 → ceil(1) = 1 → sorted[0] (lower median). round-based 구현은
    # sorted[1] (=max)을 골라 latency 과대 보고했음 — 회귀 가드.
    base = 1.hour.ago
    [ 2, 10 ].each do |delta|
      @workspace.parsing_sessions.create!(
        source_type: "file_upload", status: "completed",
        review_status: "committed",
        completed_at: base, committed_at: base + delta.seconds
      )
    end

    report = ImportReviewMetricsReport.new(
      sessions: @workspace.parsing_sessions,
      options: { workspace_id: @workspace.id }
    ).render

    assert_match(/p50:\s+2s/, report)
    refute_match(/p50:\s+10s/, report)
  end

  test "exclusion rate counts rolled_back rows (covers duplicate keep_original)" do
    # 중복 결정이 새 row를 rolled_back으로 만들면 transaction_excluded 이벤트
    # 없이도 분자에 잡혀야 함. status: rolled_back으로 numerator 산출.
    session = @workspace.parsing_sessions.create!(
      source_type: "file_upload", status: "completed",
      review_status: "committed",
      completed_at: 2.minutes.ago, committed_at: 1.minute.ago
    )
    @workspace.transactions.create!(date: Date.current, amount: 1, status: "committed", parsing_session: session)
    # 중복 결정으로 rolled_back된 행 — 이벤트 없음
    @workspace.transactions.create!(date: Date.current, amount: 2, status: "rolled_back", parsing_session: session)

    report = ImportReviewMetricsReport.new(
      sessions: @workspace.parsing_sessions.where(id: session.id),
      options: {}
    ).render

    # 후보 2건, 제외 1건 → 50% (이벤트 없어도 잡혀야 함)
    assert_match(/Row exclusion rate.*?average exclusion rate: 50\.0%/m, report)
  end

  test "exclusion denominator includes soft-deleted rows (stability)" do
    # 사용자가 commit 후 일부 row를 TransactionsController#destroy로 soft-delete
    # 해도 baseline rate가 retroactively drift하지 않아야 함.
    session = @workspace.parsing_sessions.create!(
      source_type: "file_upload", status: "completed",
      review_status: "committed",
      completed_at: 2.minutes.ago, committed_at: 1.minute.ago
    )
    soft_deleted = @workspace.transactions.create!(date: Date.current, amount: 1, status: "committed", parsing_session: session)
    @workspace.transactions.create!(date: Date.current, amount: 2, status: "committed", parsing_session: session)
    @workspace.transactions.create!(date: Date.current, amount: 3, status: "rolled_back", parsing_session: session)

    # 사후 soft-delete
    soft_deleted.update!(deleted: true)

    report = ImportReviewMetricsReport.new(
      sessions: @workspace.parsing_sessions.where(id: session.id),
      options: {}
    ).render

    # 후보 3건 (soft-deleted 포함), 제외 1건 → 33.3% (deleted: false만 보면 50%로 drift)
    assert_match(/Row exclusion rate.*?average exclusion rate: 33\.3%/m, report)
  end

  test "status distribution sort is nil-safe" do
    # 정상적으로는 nil status가 들어가지 않지만 historical row가 있을 수 있음.
    # 분포 출력이 ArgumentError로 터지지 않는지 회귀 가드.
    @workspace.parsing_sessions.create!(source_type: "file_upload", status: "completed", review_status: "committed")
    @workspace.parsing_sessions.create!(source_type: "file_upload", status: "failed", review_status: "pending_review")

    # rake task는 무관 — 보고서 클래스가 직접 group/sort 처리 검증
    report = ImportReviewMetricsReport.new(
      sessions: @workspace.parsing_sessions,
      options: { workspace_id: @workspace.id }
    ).render

    assert_match(/Session status distribution/, report)
    refute_match(/ArgumentError/, report)
  end

  test "computes distinct-transaction modification rate per session" do
    session1 = @workspace.parsing_sessions.create!(
      source_type: "file_upload", status: "completed",
      review_status: "committed",
      completed_at: 2.minutes.ago, committed_at: 1.minute.ago
    )
    tx1a = @workspace.transactions.create!(date: Date.current, amount: 1, status: "committed", parsing_session: session1)
    @workspace.transactions.create!(date: Date.current, amount: 2, status: "committed", parsing_session: session1)
    2.times do
      @workspace.import_review_events.create!(
        parsing_session: session1, reviewed_transaction: tx1a,
        event_type: "transaction_updated", changed_fields: [ "merchant" ]
      )
    end

    @workspace.parsing_sessions.create!(
      source_type: "text_paste", status: "completed",
      review_status: "committed",
      completed_at: 5.minutes.ago, committed_at: 3.minutes.ago
    ).tap do |s|
      @workspace.transactions.create!(date: Date.current, amount: 3, status: "committed", parsing_session: s)
    end

    report = ImportReviewMetricsReport.new(
      sessions: @workspace.parsing_sessions,
      options: { workspace_id: @workspace.id }
    ).render

    assert_match(/committed sessions analyzed: 2/, report)
    assert_match(/average modification rate: 25\.0%/, report)
  end
end
