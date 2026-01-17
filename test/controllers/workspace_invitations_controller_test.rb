require "test_helper"

class WorkspaceInvitationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
    @member = users(:member)
    @workspace = workspaces(:main_workspace)
    @invitation = workspace_invitations(:active_invitation)
    sign_in @admin
  end

  test "index requires authentication" do
    sign_out @admin
    get workspace_invitations_path(@workspace)
    assert_redirected_to new_user_session_path
  end

  test "index requires admin access" do
    sign_out @admin
    sign_in @member
    get workspace_invitations_path(@workspace)
    assert_redirected_to workspace_path(@workspace)
  end

  test "index lists invitations" do
    get workspace_invitations_path(@workspace)
    assert_response :success
  end

  test "create creates invitation" do
    assert_difference 'WorkspaceInvitation.count' do
      post workspace_invitations_path(@workspace), params: {
        workspace_invitation: {
          expires_at: 7.days.from_now,
          max_uses: 5
        }
      }
    end
    assert_redirected_to settings_workspace_path(@workspace)
  end

  test "destroy deletes invitation" do
    assert_difference 'WorkspaceInvitation.count', -1 do
      delete workspace_invitation_path(@workspace, @invitation)
    end
    assert_redirected_to settings_workspace_path(@workspace)
  end

  test "join with invalid token redirects" do
    get join_workspace_path(token: 'invalid_token')
    assert_redirected_to root_path
    assert_match /유효하지 않은 초대 링크/, flash[:alert]
  end

  test "join with expired token redirects" do
    @invitation.update!(expires_at: 1.day.ago)
    get join_workspace_path(token: @invitation.token)
    assert_redirected_to root_path
    assert_match /만료되었거나 사용할 수 없는/, flash[:alert]
  end

  test "join redirects to login if not signed in" do
    sign_out @admin
    get join_workspace_path(token: @invitation.token)
    assert_redirected_to new_user_session_path
  end

  test "join adds user to workspace" do
    # Create new user who is not in the workspace
    new_user = User.create!(email: 'new@example.com', password: 'password123', name: 'New User')
    sign_out @admin
    sign_in new_user

    assert_difference 'WorkspaceMembership.count' do
      get join_workspace_path(token: @invitation.token)
    end
    assert_redirected_to workspace_path(@workspace)
  end

  test "join redirects if already member" do
    get join_workspace_path(token: @invitation.token)
    assert_redirected_to workspace_path(@workspace)
    assert_match /이미 이 워크스페이스의 멤버/, flash[:notice]
  end

  test "join with maxed out invitation redirects" do
    @invitation.update!(max_uses: 1)
    # First, use the invitation
    new_user = User.create!(email: 'first@example.com', password: 'password123', name: 'First')
    sign_out @admin
    sign_in new_user
    get join_workspace_path(token: @invitation.token)

    # Now try with another user
    another_user = User.create!(email: 'second@example.com', password: 'password123', name: 'Second')
    sign_out new_user
    sign_in another_user
    get join_workspace_path(token: @invitation.token)
    assert_redirected_to root_path
  end

  test "create with defaults works" do
    assert_difference 'WorkspaceInvitation.count' do
      post workspace_invitations_path(@workspace), params: {
        workspace_invitation: { max_uses: 10 }
      }
    end
    assert_redirected_to settings_workspace_path(@workspace)
  end

  test "non-admin cannot destroy invitation" do
    sign_out @admin
    sign_in @member
    assert_no_difference 'WorkspaceInvitation.count' do
      delete workspace_invitation_path(@workspace, @invitation)
    end
    assert_redirected_to workspace_path(@workspace)
  end

  test "non-admin cannot create invitation" do
    sign_out @admin
    sign_in @member
    assert_no_difference 'WorkspaceInvitation.count' do
      post workspace_invitations_path(@workspace), params: {
        workspace_invitation: { max_uses: 5 }
      }
    end
    assert_redirected_to workspace_path(@workspace)
  end
end
