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

  test "new slideover rejects invalid parsing_session_id (no rendered form)" do
    # 위조/stale parsing_session_id로 slideover 폼이 렌더되면 후속 POST가 id를
    # drop한 채 workspace scope로 폴백 → review-context guard 우회. new에서
    # 막아야 함.
    get new_workspace_category_path(@workspace), params: {
      slideover: "true",
      transaction_id: 1,
      parsing_session_id: 999_999_999
    }

    assert_response :not_found
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

  # Phase 5 cleanup (Scope B): finalized parsing_session에서는 슬라이드오버 경로로도
  # category 생성 + transaction mutation이 불가능해야 한다.
  # ReviewsController#reject_if_finalized 와 같은 의미. invalid id (404)만 막던 가드를
  # finalized state (committed/rolled_back/discarded)까지 확장.

  test "new slideover rejects committed parsing_session (review-context closed)" do
    ps = parsing_sessions(:completed_session)
    ps.update!(review_status: "committed")

    get new_workspace_category_path(@workspace), params: {
      slideover: "true",
      transaction_id: 1,
      parsing_session_id: ps.id
    }, as: :turbo_stream

    assert_response :not_found
  end

  test "create via slideover rejects committed parsing_session and does not persist category or mutate transaction" do
    ps = parsing_sessions(:completed_session)
    ps.update!(review_status: "committed")
    tx = @workspace.transactions.create!(
      date: Date.current, amount: 1000, merchant: "COMMITTED_SCOPE",
      status: "committed", parsing_session: ps
    )
    initial_category_id = tx.category_id
    initial_count = @workspace.categories.count

    post workspace_categories_path(@workspace), params: {
      category: { name: "신규_거부_카테고리", color: "#000000" },
      slideover: "true",
      transaction_id: tx.id,
      parsing_session_id: ps.id
    }, as: :turbo_stream

    assert_response :not_found
    assert_equal initial_count, @workspace.categories.count,
                 "finalized session에서 category가 생성되면 안 됨"
    if initial_category_id.nil?
      assert_nil tx.reload.category_id
    else
      assert_equal initial_category_id, tx.reload.category_id
    end
  end

  test "create via slideover rejects rolled_back parsing_session" do
    ps = parsing_sessions(:completed_session)
    ps.update!(review_status: "rolled_back")

    post workspace_categories_path(@workspace), params: {
      category: { name: "롤백거부카테고리", color: "#000000" },
      slideover: "true",
      transaction_id: 1,
      parsing_session_id: ps.id
    }, as: :turbo_stream

    assert_response :not_found
  end

  test "create via slideover rejects discarded parsing_session" do
    ps = parsing_sessions(:completed_session)
    ps.update!(review_status: "discarded")

    post workspace_categories_path(@workspace), params: {
      category: { name: "폐기거부카테고리", color: "#000000" },
      slideover: "true",
      transaction_id: 1,
      parsing_session_id: ps.id
    }, as: :turbo_stream

    assert_response :not_found
  end

  test "create via slideover with pending review-context limits transaction scope to pending_review rows" do
    # session.transactions.pending_review로 좁혔으므로 같은 session 안에서도
    # 이미 committed/discarded된 row는 mutation 불가.
    ps = parsing_sessions(:completed_session)
    ps.update!(review_status: "pending_review")
    finalized_row = @workspace.transactions.create!(
      date: Date.current, amount: 2000, merchant: "ROW_ALREADY_COMMITTED",
      status: "committed", parsing_session: ps
    )

    post workspace_categories_path(@workspace), params: {
      category: { name: "행단위거부", color: "#000000" },
      slideover: "true",
      transaction_id: finalized_row.id,
      parsing_session_id: ps.id
    }, as: :turbo_stream

    assert_response :not_found
    assert_nil finalized_row.reload.category_id,
               "review-context 안에서도 committed row는 mutation 거부"
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

  # ────────────────────────────────────────────────────────────────────
  # #220 Policy A regression coverage.
  #
  # Policy lock (PR #219–#231 adversarial review § P1/P2-1):
  #   finalized parsing_session 은 "review/import 컨텍스트 종료"이지 row 영구
  #   잠금이 아니다. 따라서:
  #     - parsing_session_id 가 함께 오는 review-context slideover mutation 은
  #       finalized session 에서 거부한다 (위 `rejects committed/rolled_back/
  #       discarded parsing_session` 테스트가 이미 잠금).
  #     - parsing_session_id 가 없는 일반 ledger slideover mutation 은 허용한다.
  #       사용자는 finalize 이후에도 장부 거래의 카테고리/메모 등을 고칠 수
  #       있어야 한다.
  #
  # 이 테스트들은 "finalized session 의 transaction 이라도 ledger 컨텍스트에서는
  # 수정 가능" 정책이 향후 회귀로 깨지지 않도록 한다. parsing_session_id 누락 →
  # workspace scope 로 fallback 하는 동작은 Codex hotfix A 가 review 컨텍스트
  # 보존을 위해 의도적으로 남겨둔 정상 경로다.
  test "create via slideover without parsing_session_id allows ledger edit even if tx belongs to a finalized session" do
    ps = parsing_sessions(:completed_session)
    ps.update!(review_status: "committed")
    tx = @workspace.transactions.create!(
      date: Date.current, amount: 1000, merchant: "LEDGER_EDIT",
      status: "committed", parsing_session: ps
    )

    assert_difference "Category.count", 1 do
      post workspace_categories_path(@workspace), params: {
        category: { name: "ledger_edit_category", color: "#000000" },
        slideover: "true",
        transaction_id: tx.id
        # parsing_session_id 의도적으로 누락 — 일반 ledger 편집 경로.
      }, as: :turbo_stream
    end

    assert_response :success
    created = @workspace.categories.find_by(name: "ledger_edit_category")
    assert_not_nil created, "ledger 컨텍스트에서는 finalized session row 라도 카테고리 변경 허용"
    assert_equal created.id, tx.reload.category_id,
                 "Policy A: parsing_session_id 누락 → workspace scope fallback → 거래 카테고리 적용"
    assert_equal "manual_set", tx.classification_source,
                 "사용자가 명시적으로 만든 카테고리는 manual_set 으로 기록"
  end

  test "new slideover without parsing_session_id renders ledger form (no finalized 404)" do
    # 위 정책의 GET 대응. parsing_session_id 가 없으면 finalized session 여부를
    # 보지 않으므로 slideover form 이 정상 렌더된다.
    get new_workspace_category_path(@workspace), params: {
      slideover: "true",
      transaction_id: 1
      # parsing_session_id 의도적으로 누락.
    }, as: :turbo_stream

    assert_response :success
  end
end
