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

  # Codex review (#185 P1, line 56): #new GET이 parsing_session_id를 받았다면 그것이
  # #create POST action URL에도 들어가 있어야 한다. 누락되면 POST는 @parsing_session=nil
  # 로 들어와 workspace scope으로 fallback → row가 workspace endpoint로 변질된다.
  test "new slideover form carries parsing_session_id into POST action URL" do
    ps = parsing_sessions(:completed_session)
    ps.update!(review_status: "pending_review")
    tx = ps.transactions.create!(
      workspace: @workspace, date: Date.current, amount: 1000,
      merchant: "FORM_ACTION", status: "pending_review"
    )

    get new_workspace_category_path(@workspace),
        params: { slideover: "true", transaction_id: tx.id, parsing_session_id: ps.id }

    assert_response :success
    # form action에 parsing_session_id가 query param으로 들어 있어야 한다.
    # 정확한 query 순서/HTML escape는 Rails에 맡기고 핵심 param 존재만 검증.
    assert_select "form[action*=?]", "/workspaces/#{@workspace.id}/categories"
    assert_select "form[action*=?]", "parsing_session_id=#{ps.id}"
    assert_select "form[action*=?]", "transaction_id=#{tx.id}"
    assert_select "form[action*=?]", "slideover=true"
  end

  test "new slideover with invalid parsing_session_id is rejected at GET time" do
    # GET 단계에서도 fail-fast로 막아야 #create POST에 invalid id가 들어오는 일을 차단.
    other_ws = workspaces(:other_workspace)
    other_session = other_ws.parsing_sessions.create!(
      source_type: "text_paste", status: "completed", review_status: "pending_review",
      total_count: 0, success_count: 0, duplicate_count: 0, error_count: 0
    )

    get new_workspace_category_path(@workspace),
        params: { slideover: "true", transaction_id: 1, parsing_session_id: other_session.id }

    assert_response :not_found
  end

  test "create via slideover rejects invalid parsing_session_id (no workspace fallback)" do
    # Codex review (#185 P1): parsing_session_id가 *주어졌지만* workspace에 없으면
    # find_by → nil fallback이 @workspace.transactions로 떨어지면서 hotfix가 막으려던
    # cross-session 경로가 다시 열린다. find로 즉시 404.
    other_ws = workspaces(:other_workspace)
    other_session = other_ws.parsing_sessions.create!(
      source_type: "text_paste", status: "completed", review_status: "pending_review",
      total_count: 0, success_count: 0, duplicate_count: 0, error_count: 0
    )
    tx = @workspace.transactions.create!(
      date: Date.current, amount: 1000, merchant: "WS_FALLBACK",
      status: "committed"
    )
    initial_category_id = tx.category_id

    post workspace_categories_path(@workspace), params: {
      category: { name: "교차세션침입", color: "#000000" },
      slideover: "true",
      transaction_id: tx.id,
      parsing_session_id: other_session.id
    }, as: :turbo_stream

    assert_response :not_found
    # 카테고리는 만들어지지 않아야 하고, transaction도 변경되지 않아야 한다.
    assert_nil @workspace.categories.find_by(name: "교차세션침입")
    if initial_category_id.nil?
      assert_nil tx.reload.category_id
    else
      assert_equal initial_category_id, tx.reload.category_id
    end
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
