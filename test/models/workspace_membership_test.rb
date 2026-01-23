require "test_helper"

class WorkspaceMembershipTest < ActiveSupport::TestCase
  test "membership is valid with valid attributes" do
    membership = workspace_memberships(:admin_owner)
    assert membership.valid?
  end

  test "membership requires role" do
    membership = WorkspaceMembership.new(user: users(:admin), workspace: workspaces(:main_workspace))
    assert_not membership.valid?
    assert_includes membership.errors[:role], "can't be blank"
  end

  test "membership role must be valid" do
    membership = WorkspaceMembership.new(
      user: users(:admin),
      workspace: workspaces(:other_workspace),
      role: "invalid_role"
    )
    assert_not membership.valid?
    assert_includes membership.errors[:role], "is not included in the list"
  end

  test "user can only have one membership per workspace" do
    existing = workspace_memberships(:admin_owner)
    membership = WorkspaceMembership.new(
      user: existing.user,
      workspace: existing.workspace,
      role: "member_read"
    )
    assert_not membership.valid?
    assert_includes membership.errors[:user_id], "has already been taken"
  end

  test "admins scope returns owner and co_owner roles" do
    admins = WorkspaceMembership.admins
    admins.each do |m|
      assert_includes %w[owner co_owner], m.role
    end
  end

  test "writers scope returns owner, co_owner, and member_write roles" do
    writers = WorkspaceMembership.writers
    writers.each do |m|
      assert_includes %w[owner co_owner member_write], m.role
    end
  end

  test "admin? returns true for owner" do
    membership = workspace_memberships(:admin_owner)
    assert membership.admin?
  end

  test "admin? returns false for member_write" do
    membership = workspace_memberships(:member_writer)
    assert_not membership.admin?
  end

  test "writer? returns true for owner" do
    membership = workspace_memberships(:admin_owner)
    assert membership.writer?
  end

  test "writer? returns true for member_write" do
    membership = workspace_memberships(:member_writer)
    assert membership.writer?
  end

  test "writer? returns false for member_read" do
    membership = workspace_memberships(:reader_membership)
    assert_not membership.writer?
  end

  test "ROLES contains expected values" do
    assert_includes WorkspaceMembership::ROLES, "owner"
    assert_includes WorkspaceMembership::ROLES, "co_owner"
    assert_includes WorkspaceMembership::ROLES, "member_write"
    assert_includes WorkspaceMembership::ROLES, "member_read"
  end
end
