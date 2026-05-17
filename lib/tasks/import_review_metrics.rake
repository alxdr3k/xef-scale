# Import review metrics for Issue #187 (auto-post 결정 데이터).
#
# 본 task는 thin wrapper다. 실제 로직은 app/services에 있어 Rails autoload로
# console에서도 직접 호출 가능:
#
#   bin/rails runner 'puts ImportReviewMetricsReport.new(sessions: ParsingSession.all, options: {}).render'
#
# 사용:
#   bin/rails import_review_metrics:report
#   bin/rails 'import_review_metrics:report[--workspace=5 --since=2026-05-17]'
#
# 인자(괄호 안):
#   --workspace=ID      특정 workspace로 필터 (생략 시 전체)
#   --since=YYYY-MM-DD  parsing_session.created_at 기준 시작일
#   --until=YYYY-MM-DD  parsing_session.created_at 기준 종료일 (배타적)

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
