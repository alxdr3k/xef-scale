require "test_helper"

class ActiveStorageBlobCleanupJobTest < ActiveJob::TestCase
  setup do
    @workspace = workspaces(:main_workspace)
  end

  test "job is enqueued to default queue" do
    assert_equal "default", ActiveStorageBlobCleanupJob.new.queue_name
  end

  test "purges blob when parsing session has been in terminal state past retention" do
    pf = processed_files(:completed_file)
    attach_dummy_blob(pf)
    pf.parsing_session.update!(
      review_status: "committed",
      committed_at: 200.days.ago,
      completed_at: 200.days.ago,
      rolled_back_at: nil
    )

    assert_nil pf.blob_purged_at
    ActiveStorageBlobCleanupJob.new.perform
    assert_not_nil pf.reload.blob_purged_at
  end

  test "skips file inside retention window" do
    pf = processed_files(:completed_file)
    attach_dummy_blob(pf)
    pf.parsing_session.update!(
      review_status: "committed",
      committed_at: 30.days.ago,
      completed_at: 30.days.ago,
      rolled_back_at: nil
    )

    ActiveStorageBlobCleanupJob.new.perform
    assert_nil pf.reload.blob_purged_at
  end

  test "skips already-purged files (idempotent)" do
    pf = processed_files(:completed_file)
    attach_dummy_blob(pf)
    original_stamp = 5.days.ago
    pf.update!(blob_purged_at: original_stamp)
    pf.parsing_session.update!(
      review_status: "committed",
      committed_at: 200.days.ago,
      completed_at: 200.days.ago
    )

    ActiveStorageBlobCleanupJob.new.perform
    assert_in_delta original_stamp.to_f, pf.reload.blob_purged_at.to_f, 1.0
  end

  test "skips file whose parsing session is still pending review" do
    pf = processed_files(:completed_file)
    attach_dummy_blob(pf)
    pf.parsing_session.update!(
      status: "completed",
      review_status: "pending_review",
      completed_at: 400.days.ago,
      committed_at: nil,
      rolled_back_at: nil
    )

    ActiveStorageBlobCleanupJob.new.perform
    assert_nil pf.reload.blob_purged_at
  end

  test "processes multiple files and purges only the eligible ones" do
    eligible = processed_files(:completed_file)
    attach_dummy_blob(eligible)
    eligible.parsing_session.update!(
      review_status: "committed",
      committed_at: 200.days.ago,
      completed_at: 200.days.ago,
      rolled_back_at: nil
    )

    not_eligible = processed_files(:pending_file)
    attach_dummy_blob(not_eligible)
    # pending_file fixture is linked to pending_session; force it into a recent
    # rolled_back state so it's clearly within the retention window.
    not_eligible.parsing_session.update!(
      status: "completed",
      review_status: "rolled_back",
      completed_at: 30.days.ago,
      rolled_back_at: 30.days.ago,
      committed_at: nil
    )

    ActiveStorageBlobCleanupJob.new.perform

    assert_not_nil eligible.reload.blob_purged_at
    assert_nil not_eligible.reload.blob_purged_at
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
