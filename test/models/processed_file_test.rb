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

  test "rejects excel/csv/pdf even if uploaded by mistake" do
    %w[statement.xlsx statement.csv statement.pdf].each do |name|
      pf = ProcessedFile.new(
        workspace: workspaces(:main_workspace),
        filename: name,
        status: "pending"
      )
      pf.file.attach(
        io: StringIO.new("x"),
        filename: name,
        content_type: "application/octet-stream"
      )
      assert_not pf.valid?, "#{name} should be rejected"
      assert pf.errors[:file].any? { |msg| msg.include?("지원하지 않는 파일 형식") }
    end
  end

  test "rejects files with disallowed content type even if extension is allowed" do
    pf = ProcessedFile.new(
      workspace: workspaces(:main_workspace),
      filename: "statement.png",
      status: "pending"
    )
    pf.file.attach(
      io: StringIO.new("<script>"),
      filename: "statement.png",
      content_type: "application/x-msdownload"
    )
    assert_not pf.valid?
    assert pf.errors[:file].any? { |msg| msg.include?("콘텐츠 타입") }
  end

  test "rejects files larger than MAX_FILE_SIZE" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("x"),
      filename: "huge.png",
      content_type: "image/png"
    )
    blob.update_column(:byte_size, ProcessedFile::MAX_FILE_SIZE + 1)

    pf = ProcessedFile.new(
      workspace: workspaces(:main_workspace),
      filename: "huge.png",
      status: "pending"
    )
    pf.file.attach(blob)
    assert_not pf.valid?
    assert pf.errors[:file].any? { |msg| msg.include?("MB") }
  end

  test "accepts allowed png content type" do
    png_magic = "\x89PNG\r\n\x1A\n\x00\x00\x00\rIHDR".b
    pf = ProcessedFile.new(
      workspace: workspaces(:main_workspace),
      filename: "statement.png",
      status: "pending"
    )
    pf.file.attach(
      io: StringIO.new(png_magic),
      filename: "statement.png",
      content_type: "image/png"
    )
    assert pf.valid?, pf.errors.full_messages.join(", ")
  end

  test "rejects non-image payload masquerading as .jpg" do
    # PDF bytes under a .jpg extension — the kind of spoof that would
    # otherwise pass the extension/content_type check and be shipped to
    # Gemini Vision as an image. Either the ActiveStorage content-type
    # check or the Marcel magic-number sniff must reject it.
    pf = ProcessedFile.new(
      workspace: workspaces(:main_workspace),
      filename: "statement.jpg",
      status: "pending"
    )
    pf.file.attach(
      io: StringIO.new("%PDF-1.4\n%\xE2\xE3\xCF\xD3\nfake pdf"),
      filename: "statement.jpg",
      content_type: "image/jpeg"
    )
    assert_not pf.valid?
    assert pf.errors[:file].any? { |msg| msg.include?("콘텐츠 타입") || msg.include?("이미지가 아닙니다") },
           "expected content-type or magic-number rejection, got: #{pf.errors.full_messages.join(', ')}"
  end

  test "rejects text payload with spoofed image content_type and .jpg extension" do
    # When the caller fibs about content_type, ActiveStorage trusts them and
    # the old code would let the upload through. Marcel sniffing the
    # persisted blob bytes catches this.
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("this is plain text, not a real jpg image\n" * 4),
      filename: "note.jpg",
      content_type: "image/jpeg",
      identify: false
    )
    pf = ProcessedFile.new(
      workspace: workspaces(:main_workspace),
      filename: "note.jpg",
      status: "pending"
    )
    pf.file.attach(blob)
    assert_not pf.valid?
    assert pf.errors[:file].any? { |msg| msg.include?("이미지가 아닙니다") },
           "expected magic-number rejection, got: #{pf.errors.full_messages.join(', ')}"
  end

  test "accepts real png magic bytes" do
    png_magic = "\x89PNG\r\n\x1A\n\x00\x00\x00\rIHDR".b
    pf = ProcessedFile.new(
      workspace: workspaces(:main_workspace),
      filename: "statement.png",
      status: "pending"
    )
    pf.file.attach(
      io: StringIO.new(png_magic),
      filename: "statement.png",
      content_type: "image/png"
    )
    assert pf.valid?, pf.errors.full_messages.join(", ")
  end

  # --- ADR-0002 blob retention --------------------------------------------

  test "blob_purged? reflects blob_purged_at presence" do
    pf = processed_files(:completed_file)
    assert_not pf.blob_purged?

    pf.update!(blob_purged_at: Time.current)
    assert pf.blob_purged?
  end

  test "blob_retained scope excludes purged files" do
    retained = processed_files(:completed_file)
    purged = processed_files(:pending_file)
    purged.update!(blob_purged_at: 1.day.ago)

    assert_includes ProcessedFile.blob_retained, retained
    assert_not_includes ProcessedFile.blob_retained, purged
    assert_includes ProcessedFile.blob_purged, purged
  end

  test "blob_eligible_for_purge? false without attached file" do
    pf = processed_files(:completed_file)
    assert_not pf.file.attached?
    assert_not pf.blob_eligible_for_purge?
  end

  test "blob_eligible_for_purge? false when blob already purged" do
    pf = processed_files(:completed_file)
    attach_dummy_blob(pf)
    pf.update!(blob_purged_at: Time.current)
    assert_not pf.blob_eligible_for_purge?
  end

  test "blob_eligible_for_purge? false when no parsing session" do
    pf = ProcessedFile.create!(
      workspace: workspaces(:main_workspace),
      filename: "lonely.png",
      status: "completed"
    )
    attach_dummy_blob(pf)
    assert_nil pf.parsing_session
    assert_not pf.blob_eligible_for_purge?
  end

  test "blob_eligible_for_purge? true after retention window for committed session" do
    pf = processed_files(:completed_file)
    attach_dummy_blob(pf)
    pf.parsing_session.update!(
      review_status: "committed",
      committed_at: 200.days.ago,
      completed_at: 200.days.ago,
      rolled_back_at: nil
    )
    assert pf.blob_eligible_for_purge?(retention_days: 180)
  end

  test "blob_eligible_for_purge? false within retention window" do
    pf = processed_files(:completed_file)
    attach_dummy_blob(pf)
    pf.parsing_session.update!(
      review_status: "committed",
      committed_at: 30.days.ago,
      completed_at: 30.days.ago,
      rolled_back_at: nil
    )
    assert_not pf.blob_eligible_for_purge?(retention_days: 180)
  end

  test "blob_eligible_for_purge? uses latest terminal timestamp" do
    pf = processed_files(:completed_file)
    attach_dummy_blob(pf)
    # An old commit followed by a rollback inside the retention window keeps
    # the file retained because the rollback timestamp is the latest terminal
    # transition.
    pf.parsing_session.update!(
      review_status: "rolled_back",
      completed_at: 400.days.ago,
      committed_at: 350.days.ago,
      rolled_back_at: 30.days.ago
    )
    assert_not pf.blob_eligible_for_purge?(retention_days: 180)
  end

  test "blob_eligible_for_purge? false for completed session still pending review (regression: ADR terminal-state contract)" do
    pf = processed_files(:completed_file)
    attach_dummy_blob(pf)
    # status: "completed" + review_status: "pending_review" means parsing
    # finished but the user has not committed/rolled back/discarded yet. Even
    # 400 days later, the original blob must stay until the review is closed.
    pf.parsing_session.update!(
      status: "completed",
      review_status: "pending_review",
      completed_at: 400.days.ago,
      committed_at: nil,
      rolled_back_at: nil
    )
    assert_not pf.blob_eligible_for_purge?(retention_days: 180)
  end

  test "blob_eligible_for_purge? true for failed session after retention window" do
    pf = processed_files(:completed_file)
    attach_dummy_blob(pf)
    pf.parsing_session.update!(
      status: "failed",
      review_status: nil,
      completed_at: 200.days.ago,
      committed_at: nil,
      rolled_back_at: nil
    )
    assert pf.blob_eligible_for_purge?(retention_days: 180)
  end

  test "blob_eligible_for_purge? uses discarded_at for discarded sessions" do
    pf = processed_files(:completed_file)
    attach_dummy_blob(pf)
    pf.parsing_session.update!(
      review_status: "discarded",
      committed_at: nil,
      rolled_back_at: nil,
      completed_at: nil,
      discarded_at: 200.days.ago
    )
    assert pf.blob_eligible_for_purge?(retention_days: 180)
  end

  test "blob_eligible_for_purge? is unaffected by unrelated edits after discard (regression: ADR-0002 stable cutoff)" do
    pf = processed_files(:completed_file)
    attach_dummy_blob(pf)
    pf.parsing_session.update!(
      review_status: "discarded",
      committed_at: nil,
      rolled_back_at: nil,
      completed_at: nil,
      discarded_at: 200.days.ago
    )
    # Simulate a later inline_update bumping notes/updated_at by 30 days ago.
    # discarded_at must remain the source of truth so the file is still
    # eligible for purge.
    pf.parsing_session.update!(notes: "user added a note later")
    assert pf.parsing_session.updated_at > 31.days.ago,
           "sanity: updated_at should have moved forward"
    assert pf.blob_eligible_for_purge?(retention_days: 180)
  end

  test "blob_eligible_for_purge? false when discarded_at is nil (predates column, never set)" do
    pf = processed_files(:completed_file)
    attach_dummy_blob(pf)
    pf.parsing_session.update_columns(
      review_status: "discarded",
      committed_at: nil,
      rolled_back_at: nil,
      completed_at: nil,
      discarded_at: nil
    )
    assert_not pf.blob_eligible_for_purge?(retention_days: 180)
  end

  test "purge_blob! stamps blob_purged_at and schedules detach" do
    pf = processed_files(:completed_file)
    attach_dummy_blob(pf)
    frozen_now = Time.zone.parse("2026-05-15 12:00:00")

    assert pf.purge_blob!(now: frozen_now)
    assert_equal frozen_now, pf.reload.blob_purged_at
  end

  test "purge_blob! is a no-op when already purged" do
    pf = processed_files(:completed_file)
    attach_dummy_blob(pf)
    pf.update!(blob_purged_at: 1.day.ago)

    assert_not pf.purge_blob!
  end

  private

  def attach_dummy_blob(pf)
    png_magic = "\x89PNG\r\n\x1A\n\x00\x00\x00\rIHDR".b
    pf.file.attach(
      io: StringIO.new(png_magic),
      filename: pf.filename,
      content_type: "image/png"
    )
  end
end
