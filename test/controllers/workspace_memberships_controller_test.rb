require "test_helper"

class WorkspaceMembershipsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
    @member = users(:member)
    @workspace = workspaces(:main_workspace)
    sign_in @admin
  end

  test "index requires authentication" do
    sign_out @admin
    get workspace_memberships_path(@workspace), as: :html
    assert_redirected_to new_user_session_path
  end

  test "index requires admin access" do
    sign_out @admin
    sign_in @member
    get workspace_memberships_path(@workspace), as: :html
    assert_redirected_to workspace_path(@workspace)
  end

  test "index lists memberships" do
    get workspace_memberships_path(@workspace), as: :html
    assert_response :success
  end

  test "update changes member role" do
    membership = @workspace.workspace_memberships.find_by(user: @member)
    patch workspace_membership_path(@workspace, membership), params: {
      workspace_membership: { role: 'member_read' }
    }
    assert_redirected_to settings_workspace_path(@workspace)
    assert_equal 'member_read', membership.reload.role
  end

  test "update cannot change owner role" do
    owner_membership = @workspace.workspace_memberships.find_by(role: 'owner')
    patch workspace_membership_path(@workspace, owner_membership), params: {
      workspace_membership: { role: 'member_read' }
    }
    assert_redirected_to settings_workspace_path(@workspace)
    assert_match /소유자의 역할은 변경할 수 없습니다/, flash[:alert]
  end

  test "destroy removes member" do
    membership = @workspace.workspace_memberships.find_by(user: @member)
    assert_difference 'WorkspaceMembership.count', -1 do
      delete workspace_membership_path(@workspace, membership)
    end
    assert_redirected_to settings_workspace_path(@workspace)
  end

  test "destroy cannot remove owner" do
    owner_membership = @workspace.workspace_memberships.find_by(role: 'owner')
    assert_no_difference 'WorkspaceMembership.count' do
      delete workspace_membership_path(@workspace, owner_membership)
    end
    assert_redirected_to settings_workspace_path(@workspace)
    assert_match /소유자는 제거할 수 없습니다/, flash[:alert]
  end
end
