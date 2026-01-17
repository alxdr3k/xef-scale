require "test_helper"

class WorkspacesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:admin)
    @workspace = workspaces(:main_workspace)
    sign_in @user
  end

  test "index requires authentication" do
    sign_out @user
    get workspaces_path
    assert_redirected_to new_user_session_path
  end

  test "index lists user workspaces" do
    get workspaces_path
    assert_response :success
    assert_select "h1", text: /워크스페이스/
  end

  test "show displays workspace" do
    get workspace_path(@workspace), as: :html
    assert_response :success
  end

  test "new displays form" do
    get new_workspace_path
    assert_response :success
  end

  test "create creates workspace" do
    assert_difference 'Workspace.count' do
      post workspaces_path, params: { workspace: { name: 'New Workspace' } }
    end
    assert_redirected_to workspace_path(Workspace.last)
  end

  test "create fails with invalid params" do
    assert_no_difference 'Workspace.count' do
      post workspaces_path, params: { workspace: { name: '' } }
    end
    assert_response :unprocessable_entity
  end

  test "edit displays form for admin" do
    get edit_workspace_path(@workspace), as: :html
    assert_response :success
  end

  test "update updates workspace" do
    patch workspace_path(@workspace), params: { workspace: { name: 'Updated Name' } }
    assert_redirected_to workspace_path(@workspace)
    assert_equal 'Updated Name', @workspace.reload.name
  end

  test "destroy deletes workspace" do
    workspace = Workspace.create!(name: 'To Delete', owner: @user)
    assert_difference 'Workspace.count', -1 do
      delete workspace_path(workspace)
    end
    assert_redirected_to workspaces_path
  end

  test "settings displays workspace settings" do
    get settings_workspace_path(@workspace)
    assert_response :success
  end

  test "non-admin cannot access settings" do
    sign_out @user
    sign_in users(:member)
    get settings_workspace_path(@workspace)
    assert_redirected_to workspace_path(@workspace)
  end

  test "accessing nonexistent workspace redirects to workspaces index" do
    get workspace_path(id: 9999), as: :html
    assert_redirected_to workspaces_path
  end

  test "edit redirects non-admin" do
    sign_out @user
    sign_in users(:member)
    get edit_workspace_path(@workspace)
    assert_redirected_to workspace_path(@workspace)
  end

  test "update redirects non-admin" do
    sign_out @user
    sign_in users(:member)
    patch workspace_path(@workspace), params: { workspace: { name: 'Hacked' } }
    assert_redirected_to workspace_path(@workspace)
    assert_not_equal 'Hacked', @workspace.reload.name
  end

  test "destroy redirects non-admin" do
    sign_out @user
    sign_in users(:member)
    assert_no_difference 'Workspace.count' do
      delete workspace_path(@workspace)
    end
    assert_redirected_to workspace_path(@workspace)
  end

  test "update fails with invalid params" do
    patch workspace_path(@workspace), params: { workspace: { name: '' } }
    assert_response :unprocessable_entity
  end
end
