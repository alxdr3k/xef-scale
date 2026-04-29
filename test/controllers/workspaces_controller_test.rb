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

  test "show ignores out-of-range date params instead of 500ing" do
    get workspace_path(@workspace, year: 999_999, month: 13), as: :html
    assert_response :success
  end

  test "show ignores non-integer date params" do
    get workspace_path(@workspace, year: "abc", month: "xyz"), as: :html
    assert_response :success
  end

  test "new displays form" do
    get new_workspace_path
    assert_response :success
  end

  test "create creates workspace" do
    assert_difference "Workspace.count" do
      post workspaces_path, params: { workspace: { name: "New Workspace" } }
    end
    assert_redirected_to dashboard_path
  end

  test "create fails with invalid params" do
    assert_no_difference "Workspace.count" do
      post workspaces_path, params: { workspace: { name: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "edit displays form for admin" do
    get edit_workspace_path(@workspace), as: :html
    assert_response :success
  end

  test "update updates workspace" do
    patch workspace_path(@workspace), params: { workspace: { name: "Updated Name" } }
    assert_redirected_to workspace_path(@workspace)
    assert_equal "Updated Name", @workspace.reload.name
  end

  test "destroy deletes workspace" do
    workspace = Workspace.create!(name: "To Delete", owner: @user)
    assert_difference "Workspace.count", -1 do
      delete workspace_path(workspace)
    end
    assert_redirected_to workspaces_path
  end

  test "settings displays workspace settings" do
    get settings_workspace_path(@workspace)
    assert_response :success
    assert_select "h2", text: "월 예산"
    assert_select "input[name='budget[monthly_amount]'][value=?]", @workspace.budget.monthly_amount.to_s
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
    patch workspace_path(@workspace), params: { workspace: { name: "Hacked" } }
    assert_redirected_to workspace_path(@workspace)
    assert_not_equal "Hacked", @workspace.reload.name
  end

  test "non-admin cannot update budget settings" do
    sign_out @user
    sign_in users(:member)

    assert_no_difference "Budget.count" do
      patch workspace_path(@workspace), params: {
        settings_context: "budget",
        budget: { monthly_amount: "" }
      }
    end

    assert_redirected_to workspace_path(@workspace)
    assert @workspace.reload.budget.present?
  end

  test "update budget settings creates monthly budget" do
    @workspace.budget.destroy!

    assert_difference "Budget.count", 1 do
      patch workspace_path(@workspace), params: {
        settings_context: "budget",
        budget: { monthly_amount: "750000" }
      }
    end

    assert_redirected_to settings_workspace_path(@workspace)
    assert_equal 750_000, @workspace.reload.budget.monthly_amount
  end

  test "update budget settings accepts comma formatted amount" do
    patch workspace_path(@workspace), params: {
      settings_context: "budget",
      budget: { monthly_amount: "850,000" }
    }

    assert_redirected_to settings_workspace_path(@workspace)
    assert_equal 850_000, @workspace.reload.budget.monthly_amount
  end

  test "blank budget settings clears monthly budget" do
    assert_difference "Budget.count", -1 do
      patch workspace_path(@workspace), params: {
        settings_context: "budget",
        budget: { monthly_amount: "" }
      }
    end

    assert_redirected_to settings_workspace_path(@workspace)
    assert_nil @workspace.reload.budget
  end

  test "invalid budget settings renders settings" do
    patch workspace_path(@workspace), params: {
      settings_context: "budget",
      budget: { monthly_amount: "0" }
    }

    assert_response :unprocessable_entity
    assert_select "h2", text: "월 예산"
    assert_select ".text-red-700"
  end

  test "destroy redirects non-admin" do
    sign_out @user
    sign_in users(:member)
    assert_no_difference "Workspace.count" do
      delete workspace_path(@workspace)
    end
    assert_redirected_to workspace_path(@workspace)
  end

  test "update fails with invalid params" do
    patch workspace_path(@workspace), params: { workspace: { name: "" } }
    assert_response :unprocessable_entity
  end
end
