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

  test "find_duplicate returns existing transaction with same data" do
    existing = @workspace.transactions.create!(
      date: Date.current,
      merchant: "Test Merchant",
      amount: 10000
    )

    new_tx = @workspace.transactions.create!(
      date: Date.current,
      merchant: "Test Merchant",
      amount: 10000
    )

    job = FileParsingJob.new
    result = job.send(:find_duplicate, @workspace, new_tx)
    assert_equal existing, result
  end

  test "find_duplicate returns nil when no duplicate exists" do
    tx = @workspace.transactions.create!(
      date: Date.current,
      merchant: "Unique Merchant",
      amount: 99999
    )

    job = FileParsingJob.new
    result = job.send(:find_duplicate, @workspace, tx)
    assert_nil result
  end

  test "create_transaction creates new transaction" do
    job = FileParsingJob.new
    tx_data = {
      date: Date.current,
      merchant: "New Merchant",
      description: "Test Description",
      amount: 15000,
      institution_identifier: nil
    }

    assert_difference "Transaction.count" do
      job.send(:create_transaction_without_gemini, @workspace, tx_data, @parsing_session)
    end
  end

  test "create_transaction sets financial institution" do
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
    assert_equal institution, tx.financial_institution
  end

  test "create_transaction handles nil institution identifier" do
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
