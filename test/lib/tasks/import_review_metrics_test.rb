require "test_helper"
require "rake"

# Load the rake task file so its top-level classes (ImportReviewMetricsCli,
# ImportReviewMetricsReport) are available to the tests. Skip the namespace
# registration if rails-loaded tasks already cover it.
load Rails.root.join("lib/tasks/import_review_metrics.rake").to_s

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
    # YYYY-MM-DD shape matches regex but is not a real date — must not crash.
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

    assert_includes output, "Session termination distribution"
    assert_includes output, "Row modification rate"
    assert_includes output, "ImportIssue distribution"
    assert_includes output, "Commit latency"
    assert_includes output, "Sessions in scope: 0"
  end

  test "modification rate uses reviewable scope (excludes rolled_back rows)" do
    # 3개 거래 중 2개는 reviewable, 1개는 rolled_back. modification은 reviewable
    # 중 1건에서만 발생 → 비율은 1/2 = 50%.
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

    # 사용자가 excluded row를 수정한 뒤 제외했더라도 수정 비율 계산에서 제외돼야 함.
    @workspace.import_review_events.create!(
      parsing_session: session, reviewed_transaction: excluded,
      event_type: "transaction_updated", changed_fields: [ "category_id" ]
    )

    report = ImportReviewMetricsReport.new(
      sessions: @workspace.parsing_sessions.where(id: session.id),
      options: {}
    ).render

    # keeper 1건이 reviewable, 수정된 reviewable은 0건 → 0%
    assert_match(/average modification rate: 0\.0%/, report)
    refute_match(/Row modification rate.*100\.0%/m, report)

    # excluded row를 만들기 위한 변수 사용 (lint)
    assert excluded.rolled_back?
    assert keeper.committed?
  end

  test "commit latency percentiles use nearest-rank (avoids off-by-one)" do
    # 1..10초 deltas로 sessions를 만들고 p50/p90이 max로 튀지 않는지 확인.
    base = 1.hour.ago
    10.times do |i|
      delta = i + 1
      @workspace.parsing_sessions.create!(
        source_type: "file_upload", status: "completed",
        review_status: "committed",
        completed_at: base,
        committed_at: base + delta.seconds
      )
    end

    report = ImportReviewMetricsReport.new(
      sessions: @workspace.parsing_sessions,
      options: { workspace_id: @workspace.id }
    ).render

    # p90이 10s(=max)로 튀면 안 됨. nearest-rank로 idx = (9 * 0.9).round = 8 → 9s.
    # 핵심 회귀 가드: max 값 (10s)에 닿지 않아야 함.
    assert_match(/p90:\s+9s/, report)
    refute_match(/p90:\s+10s/, report)
    # p50은 nearest-rank로 sorted[5] = 6s (=== 1..10의 중앙값 convention 한 가지)
    assert_match(/p50:\s+6s/, report)
  end

  test "computes distinct-transaction modification rate per session" do
    # session 1: 2 reviewable transactions, 1 of them updated → 50%
    session1 = @workspace.parsing_sessions.create!(
      source_type: "file_upload", status: "completed",
      review_status: "committed",
      completed_at: 2.minutes.ago, committed_at: 1.minute.ago
    )
    tx1a = @workspace.transactions.create!(date: Date.current, amount: 1, status: "committed", parsing_session: session1)
    @workspace.transactions.create!(date: Date.current, amount: 2, status: "committed", parsing_session: session1)
    # Two events on the same transaction should still count as 1 modified row.
    2.times do
      @workspace.import_review_events.create!(
        parsing_session: session1, reviewed_transaction: tx1a,
        event_type: "transaction_updated", changed_fields: [ "merchant" ]
      )
    end

    # session 2: 1 reviewable transaction, untouched → 0%
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
    # 평균 50% + 0% / 2 = 25%
    assert_match(/average modification rate: 25\.0%/, report)
  end
end
