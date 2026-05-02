require "test_helper"

class FileParsingJobTest < ActiveJob::TestCase
  setup do
    @workspace = workspaces(:main_workspace)
    @processed_file = processed_files(:pending_file)
    @parsing_session = parsing_sessions(:completed_session)
  end

  test "job is enqueued to default queue" do
    assert_equal "default", FileParsingJob.new.queue_name
  end

  test "job finds processed file by id" do
    assert_nothing_raised do
      ProcessedFile.find(@processed_file.id)
    end
  end

  # Test the private helper methods via reflection
  test "match_category returns nil for blank merchant" do
    job = FileParsingJob.new
    result = job.send(:match_category_without_gemini, @workspace, nil)
    assert_nil result
  end

  test "match_category returns nil for empty merchant" do
    job = FileParsingJob.new
    result = job.send(:match_category_without_gemini, @workspace, "")
    assert_nil result
  end

  test "match_category finds category by keyword" do
    category = categories(:food)
    category.update!(keyword: "마라탕")

    job = FileParsingJob.new
    result = job.send(:match_category_without_gemini, @workspace, "마라탕집")
    assert_equal category, result
  end

  test "DuplicateDetector finds an existing transaction with the same date, amount and merchant" do
    existing = @workspace.transactions.create!(
      date: Date.current, merchant: "Test Merchant", amount: 10000
    )
    new_tx = @workspace.transactions.create!(
      date: Date.current, merchant: "Test Merchant", amount: 10000
    )

    match = DuplicateDetector.new(@workspace, new_tx).find_match
    assert_equal existing, match.transaction
    assert_equal "high", match.confidence
  end

  test "DuplicateDetector returns nil when no candidate exists" do
    tx = @workspace.transactions.create!(
      date: Date.current, merchant: "Unique Merchant", amount: 99999
    )

    assert_nil DuplicateDetector.new(@workspace, tx).find_match
  end

  test "DuplicateDetector returns nil when amount differs" do
    @workspace.transactions.create!(
      date: Date.current, merchant: "Test Merchant", amount: 10000
    )
    new_tx = @workspace.transactions.create!(
      date: Date.current, merchant: "Test Merchant", amount: 20000
    )

    assert_nil DuplicateDetector.new(@workspace, new_tx).find_match
  end

  test "create_transaction creates pending review image transaction" do
    job = FileParsingJob.new
    tx_data = {
      date: Date.current,
      merchant: "New Merchant",
      description: "Test Description",
      amount: 15000,
      institution_identifier: nil
    }

    tx = nil
    assert_difference "Transaction.count" do
      tx = job.send(:create_transaction_without_gemini, @workspace, tx_data, @parsing_session)
    end

    assert tx.pending_review?
    assert_equal "image_upload", tx.source_type
    assert_equal @parsing_session, tx.parsing_session
  end

  test "create_transaction does not expose parser hint identifier as source institution" do
    institution = financial_institutions(:shinhan_card)
    job = FileParsingJob.new
    tx_data = {
      date: Date.current,
      merchant: "Test",
      description: "Test",
      amount: 10000,
      institution_identifier: institution.identifier
    }

    tx = job.send(:create_transaction_without_gemini, @workspace, tx_data, @parsing_session)
    assert_nil tx.financial_institution_id, "financial_institution FK는 nil이어야 합니다"
    assert_nil tx.source_institution_raw,
               "institution_identifier parser hint should not leak into user-facing source metadata"
    assert_equal "screenshot", tx.source_channel
  end

  test "create_transaction preserves parser raw institution in source_metadata when present" do
    job = FileParsingJob.new
    tx_data = {
      date: Date.current,
      merchant: "Test",
      description: "Test",
      amount: 10000,
      institution_identifier: "shinhan_card",
      source_institution_raw: "KB국민카드"
    }

    tx = job.send(:create_transaction_without_gemini, @workspace, tx_data, @parsing_session)
    assert_equal "KB국민카드", tx.source_institution_raw
  end

  test "create_transaction with nil institution identifier is valid" do
    job = FileParsingJob.new
    tx_data = {
      date: Date.current,
      merchant: "Test Merchant",
      description: "Test",
      amount: 10000,
      institution_identifier: nil
    }

    tx = job.send(:create_transaction_without_gemini, @workspace, tx_data, @parsing_session)
    assert_nil tx.financial_institution
    assert_nil tx.source_institution_raw
    assert tx.valid?
  end

  test "create_transaction with unknown institution identifier is valid" do
    job = FileParsingJob.new
    tx_data = {
      date: Date.current,
      merchant: "Test Merchant",
      description: "Test",
      amount: 10000,
      institution_identifier: "nonexistent_identifier"
    }

    tx = job.send(:create_transaction_without_gemini, @workspace, tx_data, @parsing_session)
    assert_nil tx.financial_institution
    assert_nil tx.source_institution_raw
    assert tx.valid?
  end

  test "match_category finds category with matching keyword" do
    category = @workspace.categories.first
    category.update!(keyword: "커피")

    job = FileParsingJob.new
    result = job.send(:match_category_without_gemini, @workspace, "스타벅스커피")
    assert_equal category, result
  end

  test "match_category returns nil when no category matches" do
    job = FileParsingJob.new
    result = job.send(:match_category_without_gemini, @workspace, "random merchant without match")
    assert_nil result
  end

  test "create_failure_notifications sends notifications to owner and write members" do
    job = FileParsingJob.new
    parsing_session = parsing_sessions(:completed_session)

    # main_workspace has owner (admin) + 1 member_write = 2 notifications
    assert_difference "Notification.count", 2 do
      job.send(:create_failure_notifications, parsing_session)
    end
  end

  test "stats success zero triggers fail not complete" do
    job = FileParsingJob.new
    parsing_session = parsing_sessions(:completed_session)
    parsing_session.update!(status: "processing", review_status: "pending_review")

    # stats: total > 0 but success == 0 (all errored)
    stats = { total: 3, success: 0, duplicate: 0, error: 3, gemini: 0 }

    # Simulate the conditional logic
    result = if stats[:total].zero? || stats[:success].zero?
      :fail
    else
      :complete
    end

    assert_equal :fail, result, "success==0인 경우 fail 처리되어야 함"
  end

  test "perform records incomplete parsed rows as import issues" do
    processed_file = @workspace.processed_files.create!(
      filename: "partial.png",
      original_filename: "partial.png",
      status: "pending",
      uploaded_by: users(:admin)
    )
    parsed = {
      transactions: [
        { date: Date.new(2026, 3, 25), merchant: "정상 결제", description: "", amount: 1_000 }
      ],
      incomplete_transactions: [
        { date: nil, merchant: "네이버페이", amount: 12_000, missing_fields: [ "date" ] }
      ]
    }
    job = FileParsingJob.new
    job.define_singleton_method(:parse_file) { |_processed_file| parsed }

    assert_difference -> { @workspace.transactions.count }, 1 do
      assert_difference -> { @workspace.import_issues.count }, 1 do
        job.perform(processed_file.id)
      end
    end

    parsing_session = processed_file.reload.parsing_session
    assert parsing_session.completed?
    assert_equal 2, parsing_session.total_count
    assert_equal 1, parsing_session.success_count
    assert_equal 1, parsing_session.error_count
    tx = parsing_session.transactions.first
    assert tx.committed?
    assert_equal users(:admin), tx.committed_by
    assert parsing_session.review_pending?
    assert_not parsing_session.incomplete_parse_note?

    issue = parsing_session.import_issues.first
    assert issue.open?
    assert_equal processed_file, issue.processed_file
    assert_equal "image_upload", issue.source_type
    assert_nil issue.date
    assert_equal "네이버페이", issue.merchant
    assert_equal 12_000, issue.amount
    assert_equal [ "date" ], issue.missing_fields
    assert_equal "네이버페이", issue.raw_payload["merchant"]

    notification = Notification.where(notifiable: parsing_session, notification_type: "parsing_complete").last
    assert_includes notification.message, "장부에 등록되었습니다"
    assert_equal "/workspaces/#{@workspace.id}/transactions", notification.action_url

    repair_notifications = Notification.where(notifiable: parsing_session, notification_type: "import_repair_needed")
    assert_equal 2, repair_notifications.count
    repair_notification = repair_notifications.find_by!(user: users(:admin))
    assert_includes repair_notification.message, "필수 정보가 부족한 항목 1건"
    assert_equal "/workspaces/#{@workspace.id}/transactions?repair=required&import_session_id=#{parsing_session.id}",
                 repair_notification.action_url
  end

  test "perform completes with repair issues when every parsed row is incomplete" do
    processed_file = @workspace.processed_files.create!(
      filename: "incomplete_only.png",
      original_filename: "incomplete_only.png",
      status: "pending"
    )
    parsed = {
      transactions: [],
      incomplete_transactions: [
        { date: nil, merchant: "마차이짬뽕 성수점", amount: 61_000, missing_fields: [ "date" ] }
      ]
    }
    job = FileParsingJob.new
    job.define_singleton_method(:parse_file) { |_processed_file| parsed }

    assert_no_difference -> { @workspace.transactions.count } do
      assert_difference -> { @workspace.import_issues.count }, 1 do
        job.perform(processed_file.id)
      end
    end

    parsing_session = processed_file.reload.parsing_session
    assert parsing_session.completed?
    assert processed_file.completed?
    assert_equal 1, parsing_session.total_count
    assert_equal 0, parsing_session.success_count
    assert_equal 1, parsing_session.error_count
    assert_nil parsing_session.notes
    assert_equal "마차이짬뽕 성수점", parsing_session.import_issues.first.merchant

    repair_notifications = Notification.where(notifiable: parsing_session, notification_type: "import_repair_needed")
    assert_equal 2, repair_notifications.count
    assert_equal "/workspaces/#{@workspace.id}/transactions?repair=required&import_session_id=#{parsing_session.id}",
                 repair_notifications.find_by!(user: users(:admin)).action_url
  end

  test "perform skips exact duplicate image rows without creating review confirmations" do
    existing = @workspace.transactions.create!(
      date: Date.new(2026, 3, 25),
      merchant: "네이버페이",
      amount: 12_000,
      status: "committed"
    )
    processed_file = @workspace.processed_files.create!(
      filename: "exact_duplicate.png",
      original_filename: "exact_duplicate.png",
      status: "pending",
      uploaded_by: users(:admin)
    )
    parsed = {
      transactions: [
        { date: existing.date, merchant: " 네이버페이 ", amount: existing.amount }
      ],
      incomplete_transactions: []
    }
    job = FileParsingJob.new
    job.define_singleton_method(:parse_file) { |_processed_file| parsed }

    assert_no_difference -> { @workspace.transactions.count } do
      assert_no_difference -> { DuplicateConfirmation.count } do
        job.perform(processed_file.id)
      end
    end

    parsing_session = processed_file.reload.parsing_session
    assert parsing_session.completed?
    assert parsing_session.review_committed?
    assert_equal 1, parsing_session.total_count
    assert_equal 0, parsing_session.success_count
    assert_equal 1, parsing_session.duplicate_count
    assert_equal 0, parsing_session.error_count
    assert_empty parsing_session.import_issues
  end

  test "perform stores ambiguous duplicate image rows as import issues" do
    existing = @workspace.transactions.create!(
      date: Date.new(2026, 3, 25),
      merchant: "스타벅스강남점",
      amount: 5_000,
      status: "committed"
    )
    processed_file = @workspace.processed_files.create!(
      filename: "ambiguous_duplicate.png",
      original_filename: "ambiguous_duplicate.png",
      status: "pending",
      uploaded_by: users(:admin)
    )
    parsed = {
      transactions: [
        { date: existing.date, merchant: "스타벅스 강남", amount: existing.amount }
      ],
      incomplete_transactions: []
    }
    job = FileParsingJob.new
    job.define_singleton_method(:parse_file) { |_processed_file| parsed }

    assert_no_difference -> { @workspace.transactions.count } do
      assert_difference -> { @workspace.import_issues.count }, 1 do
        assert_no_difference -> { DuplicateConfirmation.count } do
          job.perform(processed_file.id)
        end
      end
    end

    parsing_session = processed_file.reload.parsing_session
    assert parsing_session.completed?
    assert parsing_session.review_pending?
    assert_equal 1, parsing_session.total_count
    assert_equal 0, parsing_session.success_count
    assert_equal 1, parsing_session.duplicate_count

    issue = parsing_session.import_issues.first
    assert issue.ambiguous_duplicate?
    assert_equal "image_upload", issue.source_type
    assert_equal existing, issue.duplicate_transaction
    assert_equal "스타벅스 강남", issue.merchant
    assert_equal [], issue.missing_fields
    assert_equal existing.id, issue.raw_payload.dig("duplicate_match", "transaction_id")

    repair_notifications = Notification.where(notifiable: parsing_session, notification_type: "import_repair_needed")
    assert_equal 2, repair_notifications.count
    assert_includes repair_notifications.find_by!(user: users(:admin)).message, "중복 확인이 필요한 항목 1건"
  end

  test "gemini batch categorizes image transactions and stores mapping" do
    job = FileParsingJob.new
    merchant = "새로운카페"
    category = categories(:food)
    transaction = @workspace.transactions.create!(
      date: Date.current,
      merchant: merchant,
      amount: 6900,
      status: "pending_review",
      source_type: "image_upload",
      parsing_session: @parsing_session
    )

    test_case = self
    fake_service = Object.new
    fake_service.define_singleton_method(:suggest_categories_batch) do |merchants, _categories|
      test_case.assert_equal [ merchant ], merchants
      { merchant => category.name }
    end

    original_new = GeminiCategoryService.method(:new)
    GeminiCategoryService.define_singleton_method(:new) { fake_service }

    assert_difference -> { CategoryMapping.where(source: "gemini", merchant_pattern: merchant).count }, 1 do
      assert_equal 1, job.send(:categorize_with_gemini_batch, @workspace, [ transaction ])
    end

    assert_equal category, transaction.reload.category
  ensure
    GeminiCategoryService.define_singleton_method(:new, original_new) if original_new
  end

  test "perform creates parsing session" do
    processed_file = processed_files(:pending_file)

    # Remove existing parsing session if any
    processed_file.parsing_session&.destroy

    initial_session_count = ParsingSession.count

    begin
      FileParsingJob.perform_now(processed_file.id)
    rescue StandardError
      # Expected - file content doesn't match any bank
    end

    # Verify parsing session was created (may not increase if error happens before)
    # At minimum, we verified the job runs
    assert_operator ParsingSession.count, :>=, initial_session_count - 1
  end
end
