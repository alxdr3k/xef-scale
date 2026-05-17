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

  # Codex hotfix A: 슬라이드오버가 review 화면에서 열렸으면 row re-render가 review
  # 컨텍스트를 유지해야 한다 — workspace-level route로 변질되면 후속 inline 편집/
  # category 변경이 reject_if_finalized 가드를 우회한다.
  test "create via slideover preserves review context when parsing_session_id given" do
    ps = parsing_sessions(:completed_session)
    ps.update!(review_status: "pending_review")
    tx = ps.transactions.create!(
      workspace: @workspace, date: Date.current, amount: 1000,
      merchant: "SLIDE_REVIEW", status: "pending_review"
    )

    post workspace_categories_path(@workspace), params: {
      category: { name: "리뷰슬라이드", color: "#123456" },
      slideover: "true",
      transaction_id: tx.id,
      parsing_session_id: ps.id
    }, as: :turbo_stream

    assert_response :success
    # row re-render의 inline edit URL은 session-scoped여야 한다.
    expected = update_transaction_workspace_parsing_session_path(@workspace, ps, transaction_id: tx.id)
    assert_match(/data-inline-edit-url-value="#{Regexp.escape(expected)}"/, response.body)
    # category selector도 session-scoped, request style은 "field"
    assert_match(/data-category-selector-update-url-value="#{Regexp.escape(expected)}"/, response.body)
    assert_match(/data-category-selector-request-style-value="field"/, response.body)
  end

  test "create via slideover rejects invalid parsing_session_id (no silent fallback)" do
    initial_count = @workspace.categories.count
    foreign_tx = @workspace.transactions.create!(
      date: Date.current, amount: 1000, merchant: "OK_TX",
      status: "pending_review", parsing_session: parsing_sessions(:completed_session)
    )

    post workspace_categories_path(@workspace), params: {
      category: { name: "쓰레기카테고리", color: "#000000" },
      slideover: "true",
      transaction_id: foreign_tx.id,
      parsing_session_id: 999_999_999 # 존재하지 않는 세션
    }, as: :turbo_stream

    assert_response :not_found
    # 카테고리도 생성되면 안 됨 (orphan 방지)
    assert_equal initial_count, @workspace.categories.count
  end

  test "create via slideover does not persist category when transaction scope check fails" do
    ps = parsing_sessions(:completed_session)
    ps.update!(review_status: "pending_review")
    initial_count = @workspace.categories.count
    foreign_tx = @workspace.transactions.create!(
      date: Date.current, amount: 1000, merchant: "FOREIGN_TX",
      status: "committed"
    )

    post workspace_categories_path(@workspace), params: {
      category: { name: "오펀카테고리", color: "#000000" },
      slideover: "true",
      transaction_id: foreign_tx.id,
      parsing_session_id: ps.id
    }, as: :turbo_stream

    assert_response :not_found
    # 분기 검증 실패 시 category가 persist되지 않아야 함 — orphan 방지
    assert_equal initial_count, @workspace.categories.count
  end

  test "create via slideover rejects transaction not belonging to parsing_session" do
    ps = parsing_sessions(:completed_session)
    ps.update!(review_status: "pending_review")
    # transaction은 parsing_session에 속하지 않음 (committed, parsing_session_id nil)
    foreign_tx = @workspace.transactions.create!(
      date: Date.current, amount: 1000, merchant: "FOREIGN_TX",
      status: "committed"
    )
    initial_category_id = foreign_tx.category_id

    post workspace_categories_path(@workspace), params: {
      category: { name: "이상한카테고리", color: "#000000" },
      slideover: "true",
      transaction_id: foreign_tx.id,
      parsing_session_id: ps.id
    }, as: :turbo_stream

    # Rails rescues ActiveRecord::RecordNotFound → 404. Transaction은 변경되지 않아야.
    assert_response :not_found
    if initial_category_id.nil?
      assert_nil foreign_tx.reload.category_id
    else
      assert_equal initial_category_id, foreign_tx.reload.category_id
    end
  end
end
