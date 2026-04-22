require "test_helper"

class ProcessedFileTest < ActiveSupport::TestCase
  test "processed file is valid with valid attributes" do
    pf = processed_files(:completed_file)
    assert pf.valid?
  end

  test "processed file belongs to workspace" do
    pf = processed_files(:completed_file)
    assert_equal workspaces(:main_workspace), pf.workspace
  end

  test "processed file has one parsing session" do
    pf = processed_files(:completed_file)
    assert_equal parsing_sessions(:completed_session), pf.parsing_session
  end

  test "file_hash identifies unique files" do
    pf1 = processed_files(:completed_file)
    pf2 = processed_files(:pending_file)
    assert_not_equal pf1.file_hash, pf2.file_hash
  end

  test "requires filename" do
    pf = ProcessedFile.new(workspace: workspaces(:main_workspace), status: "pending")
    assert_not pf.valid?
    assert_includes pf.errors[:filename], "can't be blank"
  end

  test "requires valid status" do
    pf = ProcessedFile.new(
      workspace: workspaces(:main_workspace),
      filename: "test.csv",
      status: "invalid_status"
    )
    assert_not pf.valid?
    assert_includes pf.errors[:status], "is not included in the list"
  end

  test "pending? returns true for pending status" do
    pf = processed_files(:pending_file)
    assert pf.pending?
  end

  test "processing? returns true for processing status" do
    pf = ProcessedFile.new(
      workspace: workspaces(:main_workspace),
      filename: "test.csv",
      status: "processing"
    )
    assert pf.processing?
  end

  test "completed? returns true for completed status" do
    pf = processed_files(:completed_file)
    assert pf.completed?
  end

  test "failed? returns true for failed status" do
    pf = processed_files(:failed_file)
    assert pf.failed?
  end

  test "mark_processing! updates status" do
    pf = processed_files(:pending_file)
    pf.mark_processing!
    assert pf.processing?
  end

  test "mark_completed! updates status" do
    pf = processed_files(:pending_file)
    pf.mark_completed!
    assert pf.completed?
  end

  test "mark_failed! updates status" do
    pf = processed_files(:pending_file)
    pf.mark_failed!
    assert pf.failed?
  end

  test "pending scope returns only pending files" do
    pending = ProcessedFile.pending
    pending.each { |pf| assert pf.pending? }
  end

  test "completed scope returns only completed files" do
    completed = ProcessedFile.completed
    completed.each { |pf| assert pf.completed? }
  end

  test "failed scope returns only failed files" do
    failed = ProcessedFile.failed
    failed.each { |pf| assert pf.failed? }
  end

  test "rejects files with disallowed extension" do
    pf = ProcessedFile.new(
      workspace: workspaces(:main_workspace),
      filename: "malware.exe",
      status: "pending"
    )
    pf.file.attach(
      io: StringIO.new("payload"),
      filename: "malware.exe",
      content_type: "application/octet-stream"
    )
    assert_not pf.valid?
    assert pf.errors[:file].any? { |msg| msg.include?("지원하지 않는 파일 형식") }
  end

  test "rejects files with disallowed content type even if extension is allowed" do
    pf = ProcessedFile.new(
      workspace: workspaces(:main_workspace),
      filename: "statement.csv",
      status: "pending"
    )
    pf.file.attach(
      io: StringIO.new("<script>"),
      filename: "statement.csv",
      content_type: "application/x-msdownload"
    )
    assert_not pf.valid?
    assert pf.errors[:file].any? { |msg| msg.include?("콘텐츠 타입") }
  end

  test "rejects files larger than MAX_FILE_SIZE" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("x"),
      filename: "huge.csv",
      content_type: "text/csv"
    )
    blob.update_column(:byte_size, ProcessedFile::MAX_FILE_SIZE + 1)

    pf = ProcessedFile.new(
      workspace: workspaces(:main_workspace),
      filename: "huge.csv",
      status: "pending"
    )
    pf.file.attach(blob)
    assert_not pf.valid?
    assert pf.errors[:file].any? { |msg| msg.include?("MB") }
  end

  test "accepts allowed csv content type" do
    pf = ProcessedFile.new(
      workspace: workspaces(:main_workspace),
      filename: "statement.csv",
      status: "pending"
    )
    pf.file.attach(
      io: StringIO.new("date,amount\n"),
      filename: "statement.csv",
      content_type: "text/csv"
    )
    assert pf.valid?, pf.errors.full_messages.join(", ")
  end
end
