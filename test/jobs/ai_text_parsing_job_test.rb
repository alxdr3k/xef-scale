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

  test "create_transaction records text_paste source and parse_confidence" do
    job = AiTextParsingJob.new
    tx_data = {
      date: Date.current,
      merchant: "스타벅스강남점",
      amount: 5000,
      payment_type: "lump_sum",
      confidence: 0.82
    }

    tx = job.send(:create_transaction, @workspace, tx_data, @parsing_session)

    assert_equal "text_paste", tx.source_type
    assert_in_delta 0.82, tx.parse_confidence.to_f, 0.001
  end

  test "create_transaction stores source institution in source_metadata not financial_institution" do
    job = AiTextParsingJob.new
    tx_data = {
      date: Date.current,
      merchant: "스타벅스강남점",
      amount: 5000,
      payment_type: "lump_sum",
      institution: "신한카드",
      confidence: 0.9
    }

    tx = job.send(:create_transaction, @workspace, tx_data, @parsing_session)

    assert_nil tx.financial_institution_id, "financial_institution_id는 nil이어야 합니다"
    assert_equal "신한카드", tx.source_institution_raw, "source_metadata에 원문 기관명이 저장되어야 합니다"
    assert_equal "pasted_text", tx.source_channel
  end

  test "create_transaction without institution is still valid" do
    job = AiTextParsingJob.new
    tx_data = {
      date: Date.current,
      merchant: "GS25 역삼점",
      amount: 1200,
      payment_type: "lump_sum",
      institution: nil,
      confidence: 0.75
    }

    tx = job.send(:create_transaction, @workspace, tx_data, @parsing_session)

    assert tx.valid?, "금융기관 없이도 거래가 valid해야 합니다"
    assert_nil tx.source_institution_raw
    assert tx.pending_review?
  end

  test "create_transaction does not invoke gemini category fallback" do
    job = AiTextParsingJob.new
    tx_data = {
      date: Date.current,
      merchant: "새로운카페",
      amount: 6900,
      payment_type: "lump_sum",
      institution: nil,
      confidence: 0.75
    }

    original_new = GeminiCategoryService.method(:new)
    GeminiCategoryService.define_singleton_method(:new) do
      raise "text path must not call GeminiCategoryService"
    end

    assert_nothing_raised do
      job.send(:create_transaction, @workspace, tx_data, @parsing_session)
    end
  ensure
    GeminiCategoryService.define_singleton_method(:new, original_new) if original_new
  end

  test "create_failure_notifications sends notifications to owner and write members" do
    job = AiTextParsingJob.new

    # main_workspace has owner (admin) + 1 member_write = 2 notifications
    assert_difference "Notification.count", 2 do
      job.send(:create_failure_notifications, @parsing_session)
    end
  end

  test "perform fails session when all transactions error out" do
    fake_result = {
      transactions: [
        {
          date: Date.new(2026, 3, 15),
          merchant: nil,       # nil merchant will cause create! to fail
          amount: nil,         # nil amount will cause validation failure
          institution: nil,
          payment_type: "lump_sum",
          installment_month: nil,
          installment_total: nil,
          confidence: 0.5
        }
      ],
      raw_text: @parsing_session.notes,
      model_used: "gemini-test"
    }

    original_new = AiTextParser.method(:new)
    original_parse = AiTextParser.instance_method(:parse)
    AiTextParser.define_singleton_method(:new) { |*| allocate }
    AiTextParser.define_method(:parse) { |_text| fake_result }

    begin
      AiTextParsingJob.new.perform(@parsing_session.id)
    ensure
      AiTextParser.define_singleton_method(:new, original_new)
      AiTextParser.define_method(:parse, original_parse)
    end

    # session should be failed (success == 0)
    assert @parsing_session.reload.failed?, "success==0이면 세션이 failed 상태여야 함"
  end

  test "perform persists cancellation transactions with negative amount instead of skipping" do
    fake_result = {
      transactions: [
        {
          date: Date.new(2026, 3, 15),
          merchant: "스타벅스강남점",
          amount: -50000,
          institution: "신한카드",
          payment_type: "lump_sum",
          installment_month: nil,
          installment_total: nil,
          is_cancel: true,
          confidence: 0.92
        }
      ],
      raw_text: @parsing_session.notes,
      model_used: "gemini-test"
    }

    original_new = AiTextParser.method(:new)
    original_parse = AiTextParser.instance_method(:parse)
    AiTextParser.define_singleton_method(:new) { |*| allocate }
    AiTextParser.define_method(:parse) { |_text| fake_result }

    begin
      assert_difference -> { @workspace.transactions.count }, 1 do
        AiTextParsingJob.new.perform(@parsing_session.id)
      end
    ensure
      AiTextParser.define_singleton_method(:new, original_new)
      AiTextParser.define_method(:parse, original_parse)
    end

    tx = @workspace.transactions.order(:created_at).last
    assert_equal(-50000, tx.amount, "취소 거래는 음수로 저장되어야 함")
    assert tx.committed?, "정상 파싱된 취소 거래는 자동 커밋되어야 함"
    assert_equal @parsing_session, tx.parsing_session
  end

  test "perform auto commits parsed text transactions and sends ledger completion notification" do
    fake_result = {
      transactions: [
        {
          date: Date.new(2027, 1, 15),
          merchant: "자동커밋 문자",
          amount: 450000,
          institution: "신한카드",
          payment_type: "lump_sum",
          installment_month: nil,
          installment_total: nil,
          confidence: 0.91
        }
      ],
      raw_text: @parsing_session.notes,
      model_used: "gemini-test"
    }

    original_new = AiTextParser.method(:new)
    original_parse = AiTextParser.instance_method(:parse)
    AiTextParser.define_singleton_method(:new) { |*| allocate }
    AiTextParser.define_method(:parse) { |_text| fake_result }

    begin
      assert_difference -> { @workspace.transactions.committed.count }, 1 do
        assert_difference -> {
          Notification.where(
            workspace: @workspace,
            notification_type: "budget_warning",
            target_year: 2027,
            target_month: 1
          ).count
        }, 3 do
          AiTextParsingJob.new.perform(@parsing_session.id)
        end
      end
    ensure
      AiTextParser.define_singleton_method(:new, original_new)
      AiTextParser.define_method(:parse, original_parse)
    end

    tx = @workspace.transactions.order(:created_at).last
    assert tx.committed?
    assert_nil tx.committed_by
    assert @parsing_session.reload.review_committed?

    notification = Notification.where(notifiable: @parsing_session, notification_type: "parsing_complete").last
    assert_includes notification.message, "장부에 등록되었습니다"
    assert_equal "/workspaces/#{@workspace.id}/transactions", notification.action_url
  end

  test "perform leaves parsed text rows with blank merchant pending review" do
    fake_result = {
      transactions: [
        {
          date: Date.new(2027, 3, 15),
          merchant: " ",
          amount: 12_000,
          institution: "신한카드",
          payment_type: "lump_sum",
          installment_month: nil,
          installment_total: nil,
          confidence: 0.91
        }
      ],
      raw_text: @parsing_session.notes,
      model_used: "gemini-test"
    }

    original_new = AiTextParser.method(:new)
    original_parse = AiTextParser.instance_method(:parse)
    AiTextParser.define_singleton_method(:new) { |*| allocate }
    AiTextParser.define_method(:parse) { |_text| fake_result }

    begin
      AiTextParsingJob.new.perform(@parsing_session.id)
    ensure
      AiTextParser.define_singleton_method(:new, original_new)
      AiTextParser.define_method(:parse, original_parse)
    end

    tx = @workspace.transactions.order(:created_at).last
    assert tx.pending_review?
    assert @parsing_session.reload.review_pending?

    notification = Notification.where(notifiable: @parsing_session, notification_type: "parsing_complete").last
    assert_includes notification.message, "검토해주세요"
    assert_equal "/workspaces/#{@workspace.id}/parsing_sessions/#{@parsing_session.id}/review", notification.action_url
  end

  test "perform still sends completion notification when budget alert side effect fails" do
    fake_result = {
      transactions: [
        {
          date: Date.new(2027, 4, 15),
          merchant: "후처리 실패 테스트",
          amount: 12_000,
          institution: "신한카드",
          payment_type: "lump_sum",
          installment_month: nil,
          installment_total: nil,
          confidence: 0.91
        }
      ],
      raw_text: @parsing_session.notes,
      model_used: "gemini-test"
    }

    original_new = AiTextParser.method(:new)
    original_parse = AiTextParser.instance_method(:parse)
    original_budget_alert = BudgetAlertService.method(:create_for_transactions!)
    AiTextParser.define_singleton_method(:new) { |*| allocate }
    AiTextParser.define_method(:parse) { |_text| fake_result }
    BudgetAlertService.define_singleton_method(:create_for_transactions!) { |_workspace, _transactions| raise "boom" }

    begin
      assert_nothing_raised do
        AiTextParsingJob.new.perform(@parsing_session.id)
      end
    ensure
      AiTextParser.define_singleton_method(:new, original_new)
      AiTextParser.define_method(:parse, original_parse)
      BudgetAlertService.define_singleton_method(:create_for_transactions!, original_budget_alert)
    end

    assert @parsing_session.reload.completed?
    assert @parsing_session.review_committed?
    assert @workspace.transactions.order(:created_at).last.committed?

    notification = Notification.where(notifiable: @parsing_session, notification_type: "parsing_complete").last
    assert_includes notification.message, "장부에 등록되었습니다"
  end
end
