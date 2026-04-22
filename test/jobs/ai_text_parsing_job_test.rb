require "test_helper"

class AiTextParsingJobTest < ActiveJob::TestCase
  setup do
    @workspace = workspaces(:main_workspace)
    @parsing_session = @workspace.parsing_sessions.create!(
      source_type: "text_paste",
      status: "pending",
      review_status: "pending_review",
      notes: "신한체크 승인 홍*동 50,000원 일시불 03/15 14:30 스타벅스강남점"
    )
  end

  test "create_transaction builds transactions in pending_review status" do
    job = AiTextParsingJob.new
    tx_data = {
      date: Date.current,
      merchant: "스타벅스강남점",
      amount: 5000,
      payment_type: "lump_sum"
    }

    tx = job.send(:create_transaction, @workspace, tx_data, @parsing_session)

    assert tx.pending_review?, "AI-parsed text should land in pending_review, not auto-committed"
    assert_nil tx.committed_at
    assert_equal @parsing_session, tx.parsing_session
  end
end
