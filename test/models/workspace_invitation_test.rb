require "test_helper"

class WorkspaceInvitationTest < ActiveSupport::TestCase
  test "invitation is valid with valid attributes" do
    invitation = workspace_invitations(:active_invitation)
    assert invitation.valid?
  end

  test "invitation generates token on creation" do
    invitation = WorkspaceInvitation.new(
      workspace: workspaces(:main_workspace),
      invited_by: users(:admin)
    )
    assert_nil invitation.token
    invitation.valid?
    assert_not_nil invitation.token
  end

  test "token must be unique" do
    existing = workspace_invitations(:active_invitation)
    invitation = WorkspaceInvitation.new(
      workspace: workspaces(:main_workspace),
      invited_by: users(:admin),
      token: existing.token
    )
    assert_not invitation.valid?
    assert_includes invitation.errors[:token], "has already been taken"
  end

  test "expired? returns true for expired invitation" do
    invitation = workspace_invitations(:expired_invitation)
    assert invitation.expired?
  end

  test "expired? returns false for active invitation" do
    invitation = workspace_invitations(:active_invitation)
    assert_not invitation.expired?
  end

  test "used_up? returns true when current_uses >= max_uses" do
    invitation = workspace_invitations(:used_up_invitation)
    assert invitation.used_up?
  end

  test "used_up? returns false when current_uses < max_uses" do
    invitation = workspace_invitations(:active_invitation)
    assert_not invitation.used_up?
  end

  test "usable? returns true for active and available invitation" do
    invitation = workspace_invitations(:active_invitation)
    assert invitation.usable?
  end

  test "usable? returns false for expired invitation" do
    invitation = workspace_invitations(:expired_invitation)
    assert_not invitation.usable?
  end

  test "usable? returns false for used up invitation" do
    invitation = workspace_invitations(:used_up_invitation)
    assert_not invitation.usable?
  end

  test "use! increments current_uses" do
    invitation = workspace_invitations(:active_invitation)
    initial_uses = invitation.current_uses

    assert invitation.use!
    assert_equal initial_uses + 1, invitation.reload.current_uses
  end

  test "use! returns false for unusable invitation" do
    invitation = workspace_invitations(:expired_invitation)
    assert_not invitation.use!
  end

  test "active scope excludes expired invitations" do
    active_invitations = WorkspaceInvitation.active
    assert_not_includes active_invitations, workspace_invitations(:expired_invitation)
  end

  test "available scope excludes used up invitations" do
    available_invitations = WorkspaceInvitation.available
    assert_not_includes available_invitations, workspace_invitations(:used_up_invitation)
    assert_not_includes available_invitations, workspace_invitations(:expired_invitation)
  end

  test "unlimited invitation has no max_uses" do
    invitation = workspace_invitations(:unlimited_invitation)
    assert_nil invitation.max_uses
    assert invitation.usable?
    assert_not invitation.used_up?
  end

  test "max_uses must be greater than 0" do
    invitation = WorkspaceInvitation.new(
      workspace: workspaces(:main_workspace),
      invited_by: users(:admin),
      max_uses: 0
    )
    assert_not invitation.valid?
    assert_includes invitation.errors[:max_uses], "must be greater than 0"
  end

  test "expired? returns false when expires_at is nil" do
    invitation = WorkspaceInvitation.new(
      workspace: workspaces(:main_workspace),
      invited_by: users(:admin),
      expires_at: nil
    )
    assert_not invitation.expired?
  end

  test "used_up? returns false when max_uses is nil" do
    invitation = workspace_invitations(:unlimited_invitation)
    assert_nil invitation.max_uses
    assert_not invitation.used_up?
  end

  test "token is required" do
    invitation = WorkspaceInvitation.new(
      workspace: workspaces(:main_workspace),
      invited_by: users(:admin)
    )
    invitation.token = nil
    invitation.save
    # Token should be generated on save
    assert_not_nil invitation.token
  end
end
