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
