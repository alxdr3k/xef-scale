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
    assert_difference "Category.count" do
      post workspace_categories_path(@workspace), params: {
        category: { name: "새 카테고리", keyword: "키워드", color: "#FF0000" }
      }
    end
    assert_redirected_to workspace_categories_path(@workspace)
  end

  test "create renders errors for invalid params" do
    assert_no_difference "Category.count" do
      post workspace_categories_path(@workspace), params: {
        category: { name: "" }
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
      category: { name: "수정된 이름" }
    }
    assert_redirected_to workspace_categories_path(@workspace)
    assert_equal "수정된 이름", @category.reload.name
  end

  test "update renders errors for invalid params" do
    patch workspace_category_path(@workspace, @category), params: {
      category: { name: "" }
    }
    assert_response :unprocessable_entity
  end

  test "destroy deletes category" do
    category = Category.create!(name: "To Delete", workspace: @workspace)
    assert_difference "Category.count", -1 do
      delete workspace_category_path(@workspace, category)
    end
    assert_redirected_to workspace_categories_path(@workspace)
  end

  # Phase 3.4 — 카테고리 + 학습된 매핑 결합 페이지.
  test "index renders both 내 카테고리 and 학습된 매핑 sections" do
    CategoryMapping.create!(
      workspace: @workspace,
      merchant_pattern: "TEST_RECENT_MAPPING",
      match_type: "exact",
      source: "manual",
      category: @category
    )

    get workspace_categories_path(@workspace)
    assert_response :success
    assert_select "h2", text: "내 카테고리"
    assert_select "h2", text: "학습된 매핑"
    # ADR-0011 §Decision 5 ko.yml 라벨 사용 확인
    assert_includes response.body, "직접 등록"
    # 매핑이 미리보기에 노출
    assert_includes response.body, "TEST_RECENT_MAPPING"
    # 전체 보기 CTA가 category_mappings/index로 이동
    assert_includes response.body, workspace_category_mappings_path(@workspace)
  end

  test "index limits recent_mappings preview by RECENT_MAPPINGS_LIMIT" do
    # RECENT_MAPPINGS_LIMIT=10. 11개 만들고 가장 오래된 것이 미리보기에 미노출 확인.
    11.times do |i|
      CategoryMapping.create!(
        workspace: @workspace,
        merchant_pattern: "MAPPING_LIMIT_#{i}",
        match_type: "exact",
        source: "manual",
        category: @category,
        updated_at: i.minutes.ago
      )
    end

    get workspace_categories_path(@workspace)
    assert_response :success
    # 가장 최근 10건은 보임
    assert_includes response.body, "MAPPING_LIMIT_0"
    assert_includes response.body, "MAPPING_LIMIT_9"
    # 가장 오래된 1건은 미노출
    assert_not_includes response.body, "MAPPING_LIMIT_10"
  end

  # ADR-0011 §Decision 3 (PR #174 후속 fix): 슬라이드오버 "+ 새 카테고리 만들기"가
  # 거래에 적용될 때 classification_source=manual_set으로 기록되어야 한다.
  test "create via slideover with transaction_id sets transaction classification_source to manual_set" do
    tx = @workspace.transactions.create!(
      date: Date.current, amount: 1000, merchant: "SLIDE_CAT",
      category: nil, status: "committed",
      classification_source: nil
    )

    post workspace_categories_path(@workspace), params: {
      category: { name: "슬라이드신규", color: "#abcdef" },
      slideover: "true",
      transaction_id: tx.id
    }, as: :turbo_stream

    tx.reload
    new_cat = @workspace.categories.find_by(name: "슬라이드신규")
    assert_equal new_cat.id, tx.category_id
    assert_equal "manual_set", tx.classification_source
  end
end
