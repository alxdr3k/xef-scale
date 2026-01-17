require "test_helper"

class CategoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:admin)
    @workspace = workspaces(:main_workspace)
    @category = categories(:food)
    sign_in @user
  end

  test "index requires authentication" do
    sign_out @user
    get workspace_categories_path(@workspace), as: :html
    assert_redirected_to new_user_session_path
  end

  test "index requires admin access" do
    sign_out @user
    sign_in users(:member)
    get workspace_categories_path(@workspace), as: :html
    assert_redirected_to workspace_path(@workspace)
  end

  test "index lists categories" do
    get workspace_categories_path(@workspace), as: :html
    assert_response :success
  end

  test "new displays form" do
    get new_workspace_category_path(@workspace), as: :html
    assert_response :success
  end

  test "create creates category" do
    assert_difference 'Category.count' do
      post workspace_categories_path(@workspace), params: {
        category: { name: '새 카테고리', keyword: '키워드', color: '#FF0000' }
      }
    end
    assert_redirected_to workspace_categories_path(@workspace)
  end

  test "create renders errors for invalid params" do
    assert_no_difference 'Category.count' do
      post workspace_categories_path(@workspace), params: {
        category: { name: '' }
      }
    end
    assert_response :unprocessable_entity
  end

  test "edit displays form" do
    get edit_workspace_category_path(@workspace, @category), as: :html
    assert_response :success
  end

  test "update updates category" do
    patch workspace_category_path(@workspace, @category), params: {
      category: { name: '수정된 이름' }
    }
    assert_redirected_to workspace_categories_path(@workspace)
    assert_equal '수정된 이름', @category.reload.name
  end

  test "update renders errors for invalid params" do
    patch workspace_category_path(@workspace, @category), params: {
      category: { name: '' }
    }
    assert_response :unprocessable_entity
  end

  test "destroy deletes category" do
    category = Category.create!(name: 'To Delete', workspace: @workspace)
    assert_difference 'Category.count', -1 do
      delete workspace_category_path(@workspace, category)
    end
    assert_redirected_to workspace_categories_path(@workspace)
  end
end
