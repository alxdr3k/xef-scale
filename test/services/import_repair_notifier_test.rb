require "test_helper"

class ImportRepairNotifierTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:main_workspace)
    @session = @workspace.parsing_sessions.create!(
      source_type: "file_upload",
      status: "processing",
      review_status: "pending_review"
    )
    @owner = users(:admin)
    @writer = users(:member)
    @reader = users(:reader)
  end

  test "sends repair notification to owner and writers when open issues exist" do
    create_open_issue

    assert_difference -> { Notification.where(notification_type: "import_repair_needed").count }, 2 do
      ImportRepairNotifier.call(@session)
    end

    recipient_ids = Notification.where(notification_type: "import_repair_needed").pluck(:user_id)
    assert_includes recipient_ids, @owner.id
    assert_includes recipient_ids, @writer.id
    assert_not_includes recipient_ids, @reader.id
  end

  test "does not notify when no open import issues" do
    assert_no_difference -> { Notification.count } do
      ImportRepairNotifier.call(@session)
    end
  end

  test "does not send duplicate notification to owner via memberships" do
    create_open_issue

    recipient_ids = []
    # Track who would receive notifications by counting per user
    Notification.where(notification_type: "import_repair_needed").destroy_all
    ImportRepairNotifier.call(@session)

    owner_notifications = Notification.where(
      notification_type: "import_repair_needed",
      user: @owner
    ).count
    assert_equal 1, owner_notifications, "Owner should receive exactly one notification"
  end

  private

  def create_open_issue
    @session.import_issues.create!(
      workspace: @workspace,
      source_type: "image_upload",
      issue_type: "missing_required_fields",
      status: "open",
      missing_fields: %w[date],
      raw_payload: {}
    )
  end
end
