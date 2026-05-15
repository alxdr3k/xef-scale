require "test_helper"

# ADR-0002 A3: once a ProcessedFile's blob has been purged for retention, the
# UI must tell the user that the original image is no longer recoverable. The
# badge is rendered from a single shared partial; this test pins down which
# screens include it so a future refactor of the partial can't silently regress
# any of them.
class BlobPurgedIndicatorTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:admin)
    @workspace = workspaces(:main_workspace)
    @parsing_session = parsing_sessions(:completed_session)
    @processed_file = @parsing_session.processed_file
    sign_in @user
  end

  test "parsing_sessions index shows badge when blob is purged" do
    @processed_file.update!(blob_purged_at: 1.day.ago)
    get workspace_parsing_sessions_path(@workspace)
    assert_response :success
    assert_match "원본 만료", response.body
  end

  test "parsing_sessions index hides badge when blob is retained" do
    assert_nil @processed_file.blob_purged_at
    get workspace_parsing_sessions_path(@workspace)
    assert_response :success
    assert_no_match(/원본 만료/, response.body)
  end

  test "review screen shows badge when blob is purged" do
    @parsing_session.update!(review_status: "pending_review")
    @processed_file.update!(blob_purged_at: 1.day.ago)

    get review_workspace_parsing_session_path(@workspace, @parsing_session)
    assert_response :success
    assert_match "원본 만료", response.body
  end

  test "review screen hides badge when blob is retained" do
    @parsing_session.update!(review_status: "pending_review")
    assert_nil @processed_file.blob_purged_at

    get review_workspace_parsing_session_path(@workspace, @parsing_session)
    assert_response :success
    assert_no_match(/원본 만료/, response.body)
  end
end
