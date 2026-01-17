require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "user is valid with valid attributes" do
    user = users(:admin)
    assert user.valid?
  end

  test "user requires email" do
    user = User.new(password: 'password123')
    assert_not user.valid?
    assert_includes user.errors[:email], "can't be blank"
  end

  test "user requires unique email" do
    existing = users(:admin)
    user = User.new(email: existing.email, password: 'password123')
    assert_not user.valid?
    assert_includes user.errors[:email], "has already been taken"
  end

  test "from_omniauth creates new user" do
    auth = OmniAuth::AuthHash.new(
      provider: 'google_oauth2',
      uid: 'new_uid_12345',
      info: {
        email: 'newuser@example.com',
        name: 'New User',
        image: 'https://example.com/avatar.jpg'
      }
    )

    assert_difference 'User.count', 1 do
      User.from_omniauth(auth)
    end

    user = User.last
    assert_equal 'newuser@example.com', user.email
    assert_equal 'New User', user.name
  end

  test "from_omniauth finds existing user" do
    existing = users(:admin)
    auth = OmniAuth::AuthHash.new(
      provider: existing.provider,
      uid: existing.uid,
      info: {
        email: existing.email,
        name: existing.name,
        image: nil
      }
    )

    assert_no_difference 'User.count' do
      user = User.from_omniauth(auth)
      assert_equal existing.id, user.id
    end
  end

  test "admin_of? returns true for workspace owner" do
    user = users(:admin)
    workspace = workspaces(:main_workspace)
    assert user.admin_of?(workspace)
  end

  test "admin_of? returns false for non-admin member" do
    user = users(:member)
    workspace = workspaces(:main_workspace)
    assert_not user.admin_of?(workspace)
  end

  test "can_write? returns true for admin" do
    user = users(:admin)
    workspace = workspaces(:main_workspace)
    assert user.can_write?(workspace)
  end

  test "can_write? returns true for member_write" do
    user = users(:member)
    workspace = workspaces(:main_workspace)
    assert user.can_write?(workspace)
  end

  test "can_write? returns false for reader" do
    user = users(:reader)
    workspace = workspaces(:main_workspace)
    assert_not user.can_write?(workspace)
  end

  test "can_read? returns true for all members" do
    workspace = workspaces(:main_workspace)
    assert users(:admin).can_read?(workspace)
    assert users(:member).can_read?(workspace)
    assert users(:reader).can_read?(workspace)
  end

  test "can_read? returns false for non-members" do
    user = users(:other_user)
    workspace = workspaces(:main_workspace)
    assert_not user.can_read?(workspace)
  end

  test "user has many owned workspaces" do
    user = users(:admin)
    assert_includes user.owned_workspaces, workspaces(:main_workspace)
  end

  test "user has many workspaces through memberships" do
    user = users(:admin)
    assert_includes user.workspaces, workspaces(:main_workspace)
  end
end
