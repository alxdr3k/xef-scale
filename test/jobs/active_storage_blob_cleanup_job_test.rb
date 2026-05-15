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

  test "scan stays O(1) in row-fan-out queries (regression: N+1 on parsing_session/attachment)" do
    # Three retained ProcessedFile rows, all non-eligible so purge_blob! does
    # not fire and we only measure the scan cost. Without eager-loading,
    # blob_eligible_for_purge? would lazy-load parsing_session per row and the
    # attachment per row, growing linearly with the backlog.
    3.times do |i|
      pf = @workspace.processed_files.create!(
        filename: "noop_#{i}.png",
        status: "completed"
      )
      attach_dummy_blob(pf)
      pf.create_parsing_session!(
        workspace: @workspace,
        source_type: "file_upload",
        status: "completed",
        review_status: "pending_review"
      )
    end

    select_counts = Hash.new(0)
    subscriber = ->(_name, _start, _finish, _id, payload) {
      sql = payload[:sql].to_s
      next if payload[:name] == "SCHEMA"
      next unless sql.match?(/\ASELECT/i)
      table = sql[/FROM "?([a-z_]+)"?/i, 1]
      select_counts[table] += 1 if table
    }

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      ActiveStorageBlobCleanupJob.new.perform
    end

    # The Codex P2 concern was specifically that blob_eligible_for_purge?
    # dereferences parsing_session per row. With proper eager loading the
    # entire batch's parsing_sessions resolve in a single SELECT, so the
    # count must stay tight regardless of how many rows blob_retained yields.
    assert_operator select_counts["parsing_sessions"], :<=, 1,
                    "expected <= 1 parsing_sessions SELECT (eager-loaded), got #{select_counts['parsing_sessions']}"
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
