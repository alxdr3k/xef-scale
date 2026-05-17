require "test_helper"
require "csv"

class TransactionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:admin)
    @workspace = workspaces(:main_workspace)
    @transaction = transactions(:food_transaction)
    sign_in @user
  end

  test "index requires authentication" do
    sign_out @user
    get workspace_transactions_path(@workspace)
    assert_redirected_to new_user_session_path
  end

  test "index lists transactions" do
    get workspace_transactions_path(@workspace)
    assert_response :success
  end

  test "index does not render pending_badge for committed transactions" do
    get workspace_transactions_path(@workspace)
    assert_response :success
    # transactions/index uses .active scope (committed only) — pending dot must not appear
    assert_select "[aria-label='검토 대기']", count: 0
  end

  test "index renders category_source_chip with color dot for categorized rows" do
    get workspace_transactions_path(@workspace)
    assert_response :success
    cat = transactions(:food_transaction).category
    assert cat.present?, "fixture must have category"
    # _category_source_chip outer span sets background-color: #COLOR20 (8-digit
    # RGBA hex). The dropdown list items render the same color but as a solid
    # 6-digit dot (no alpha suffix), so this 8-digit pattern is unique to the
    # row chip — guards against the chip being removed while the dropdown stays.
    assert_match(/background-color:\s*#{Regexp.escape(cat.color)}20/, response.body,
                 "_category_source_chip outer span (background #COLOR20) must appear in the row")
  end

  test "index filters by year" do
    get workspace_transactions_path(@workspace, year: Date.today.year)
    assert_response :success
  end

  test "index filters by month" do
    get workspace_transactions_path(@workspace, year: Date.today.year, month: Date.today.month)
    assert_response :success
  end

  test "index filters by category" do
    get workspace_transactions_path(@workspace, category_id: categories(:food).id)
    assert_response :success
  end

  test "index ignores legacy institution filter param" do
    get workspace_transactions_path(@workspace, institution_id: financial_institutions(:shinhan_card).id)
    assert_response :success
    assert_includes response.body, transactions(:food_transaction).merchant
    assert_includes response.body, transactions(:transport_transaction).merchant
  end

  test "index searches by query" do
    get workspace_transactions_path(@workspace, q: "마라탕")
    assert_response :success
  end

  test "index ignores out-of-range month instead of crashing" do
    get workspace_transactions_path(@workspace, year: Date.current.year, month: 13)
    assert_response :success
  end

  test "index ignores non-numeric month instead of crashing" do
    get workspace_transactions_path(@workspace, year: Date.current.year, month: "abc")
    assert_response :success
  end

  test "index ignores out-of-range year instead of crashing" do
    get workspace_transactions_path(@workspace, year: 0, month: 1)
    assert_response :success
  end

  test "index hides financial institution UI and shows source popover only as metadata" do
    @transaction.update!(
      source_metadata: {
        "source_channel" => "pasted_text",
        "source_institution_raw" => "KB국민카드"
      }
    )

    get workspace_transactions_path(@workspace)

    assert_response :success
    assert_select "label", text: "금융기관", count: 0
    assert_select "th", text: "금융기관", count: 0
    assert_select "th", text: "출처", count: 1
    assert_select "button[aria-label='가져온 출처 보기']", minimum: 1
    assert_includes response.body, "원문 기관명:"
    assert_includes response.body, "KB국민카드"
  end

  test "export ignores out-of-range month instead of crashing" do
    get export_workspace_transactions_path(@workspace, format: :csv, year: Date.current.year, month: 13)
    assert_response :success
  end

  test "new displays form" do
    get new_workspace_transaction_path(@workspace)
    assert_response :success
  end

  test "create creates transaction" do
    assert_difference "Transaction.count" do
      post workspace_transactions_path(@workspace), params: {
        transaction: {
          date: Date.today,
          merchant: "Test Merchant",
          amount: 10000,
          category_id: categories(:food).id
        }
      }
    end
    assert_redirected_to workspace_transactions_path(@workspace)
    assert_equal "manual", Transaction.last.source_type
  end

  test "create fails with invalid params" do
    assert_no_difference "Transaction.count" do
      post workspace_transactions_path(@workspace), params: {
        transaction: { date: "", amount: "" }
      }
    end
    assert_response :unprocessable_entity
  end

  test "edit displays form" do
    get edit_workspace_transaction_path(@workspace, @transaction)
    assert_response :success
  end

  test "update updates transaction" do
    patch workspace_transaction_path(@workspace, @transaction), params: {
      transaction: { merchant: "Updated Merchant" }
    }
    assert_redirected_to workspace_transactions_path(@workspace)
    assert_equal "Updated Merchant", @transaction.reload.merchant
  end

  test "destroy soft deletes transaction" do
    delete workspace_transaction_path(@workspace, @transaction)
    assert_redirected_to workspace_transactions_path(@workspace)
    assert @transaction.reload.deleted
  end

  test "toggle_allowance marks as allowance" do
    post toggle_allowance_workspace_transaction_path(@workspace, @transaction)
    assert_redirected_to workspace_transactions_path(@workspace)
  end

  test "toggle_allowance removes allowance" do
    AllowanceTransaction.create!(expense_transaction: @transaction, user: @user)
    post toggle_allowance_workspace_transaction_path(@workspace, @transaction)
    assert_redirected_to workspace_transactions_path(@workspace)
  end

  test "reader cannot create transaction" do
    sign_out @user
    sign_in users(:reader)
    assert_no_difference "Transaction.count" do
      post workspace_transactions_path(@workspace), params: {
        transaction: { date: Date.today, merchant: "Test", amount: 1000 }
      }
    end
    assert_redirected_to workspace_path(@workspace)
  end


  test "export generates csv" do
    get export_workspace_transactions_path(@workspace, format: :csv)
    assert_response :success
    assert_equal "text/csv; charset=utf-8", response.content_type
  end

  test "export omits source and institution columns from default CSV" do
    get export_workspace_transactions_path(@workspace, format: :csv)

    assert_response :success
    headers = CSV.parse(response.body, headers: true).headers
    assert_equal [ "날짜", "내역", "금액", "분류", "메모" ], headers
  end

  test "export filters by year" do
    get export_workspace_transactions_path(@workspace, format: :csv, year: Date.current.year)
    assert_response :success
  end

  test "export filters by year and month" do
    get export_workspace_transactions_path(@workspace, format: :csv, year: Date.current.year, month: Date.current.month)
    assert_response :success
  end

  test "export honors category filter so it matches the index view" do
    get export_workspace_transactions_path(@workspace, format: :csv, category_id: categories(:food).id)
    assert_response :success
    body = response.body
    assert_includes body, transactions(:food_transaction).merchant
    assert_not_includes body, transactions(:transport_transaction).merchant
    assert_not_includes body, transactions(:shopping_transaction).merchant
  end

  test "export ignores legacy institution filter param" do
    get export_workspace_transactions_path(@workspace, format: :csv, institution_id: financial_institutions(:hana_card).id)
    assert_response :success
    body = response.body
    assert_includes body, transactions(:transport_transaction).merchant
    assert_includes body, transactions(:food_transaction).merchant
  end

  test "export honors search query so it matches the index view" do
    get export_workspace_transactions_path(@workspace, format: :csv, q: "마라탕")
    assert_response :success
    body = response.body
    assert_includes body, transactions(:food_transaction).merchant
    assert_not_includes body, transactions(:transport_transaction).merchant
  end


  test "quick_update_category sets the category and returns success" do
    patch quick_update_category_workspace_transaction_path(@workspace, @transaction),
          params: { category_id: categories(:transport).id },
          headers: { "Accept" => "application/json" }

    assert_response :success
    assert_equal categories(:transport).id, @transaction.reload.category_id
    body = JSON.parse(response.body)
    assert_equal true, body["success"]
  end

  # ADR-0007 §4: explicit opt-in 학습. quick_update_category / update /
  # bulk_update(change_category) 어느 경로도 CategoryMapping을 묵시적으로
  # 만들지 않는다.

  test "quick_update_category does not silently create a CategoryMapping" do
    assert_no_difference -> { CategoryMapping.count } do
      patch quick_update_category_workspace_transaction_path(@workspace, @transaction),
            params: { category_id: categories(:transport).id },
            headers: { "Accept" => "application/json" }
    end
    assert_response :success
  end

  test "update does not silently create a CategoryMapping when category changes" do
    assert_no_difference -> { CategoryMapping.count } do
      patch workspace_transaction_path(@workspace, @transaction),
            params: { transaction: { category_id: categories(:transport).id } }
    end
  end

  test "bulk_update change_category does not silently create a CategoryMapping" do
    other = @workspace.transactions.create!(
      date: Date.current, merchant: "다른가맹점", amount: 1234, status: "committed"
    )
    target = categories(:transport)

    # 실제 컨트롤러는 `bulk_action` + comma-split `transaction_ids`를 기대.
    assert_no_difference -> { CategoryMapping.count } do
      post bulk_update_workspace_transactions_path(@workspace),
           params: {
             bulk_action: "change_category",
             category_id: target.id,
             transaction_ids: "#{@transaction.id},#{other.id}"
           }
    end

    # change_category 분기가 실제로 실행됐는지 검증 (false-positive 방지).
    assert_equal target.id, @transaction.reload.category_id
    assert_equal target.id, other.reload.category_id
  end

  test "quick_update_category admin response includes inline learning suggestion when no mapping exists" do
    target_category = categories(:transport)
    refute_equal target_category.id, @transaction.category_id

    patch quick_update_category_workspace_transaction_path(@workspace, @transaction),
          params: { category_id: target_category.id },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_match(/category-learning-suggestion-#{@transaction.id}/, response.body)
    assert_match(/category-learning-suggestion#accept/, response.body)
    assert_match(/category-learning-suggestion#dismiss/, response.body)
  end

  test "quick_update_category suppresses suggestion when category did not change" do
    same = @transaction.category_id
    assert same.present?, "fixture must be categorized"

    patch quick_update_category_workspace_transaction_path(@workspace, @transaction),
          params: { category_id: same },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    # remove still appears (idempotent cleanup) but no `after` insertion of the row partial
    refute_match(/category-learning-suggestion#accept/, response.body)
  end

  test "quick_update_category suppresses suggestion when merchant is blank" do
    @transaction.update_column(:merchant, "")
    target_category = categories(:transport)

    patch quick_update_category_workspace_transaction_path(@workspace, @transaction),
          params: { category_id: target_category.id },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    refute_match(/category-learning-suggestion#accept/, response.body)
  end

  test "quick_update_category suppresses suggestion when same mapping already exists" do
    target_category = categories(:transport)
    CategoryMapping.create!(
      workspace: @workspace,
      merchant_pattern: @transaction.merchant.strip,
      description_pattern: nil,
      match_type: "exact",
      amount: nil,
      category: target_category,
      source: "manual"
    )

    patch quick_update_category_workspace_transaction_path(@workspace, @transaction),
          params: { category_id: target_category.id },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    refute_match(/category-learning-suggestion#accept/, response.body)
  end

  test "quick_update_category still offers suggestion when existing mapping points to a different category" do
    new_target = categories(:transport)
    CategoryMapping.create!(
      workspace: @workspace,
      merchant_pattern: @transaction.merchant.strip,
      description_pattern: nil,
      match_type: "exact",
      amount: nil,
      category: categories(:food),
      source: "manual"
    )

    patch quick_update_category_workspace_transaction_path(@workspace, @transaction),
          params: { category_id: new_target.id },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_match(/category-learning-suggestion#accept/, response.body)
  end

  test "quick_update_category suppresses suggestion for non-admin writers" do
    sign_out @user
    sign_in users(:member) # member_write role per fixtures
    refute users(:member).admin_of?(@workspace)

    patch quick_update_category_workspace_transaction_path(@workspace, @transaction),
          params: { category_id: categories(:transport).id },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_equal categories(:transport).id, @transaction.reload.category_id
    refute_match(/category-learning-suggestion#accept/, response.body)
  end

  test "quick_update_category rejects categories from other workspaces" do
    foreign = categories(:other_category)
    original_category_id = @transaction.category_id

    patch quick_update_category_workspace_transaction_path(@workspace, @transaction),
          params: { category_id: foreign.id },
          headers: { "Accept" => "application/json" }

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal false, body["success"]
    assert_equal original_category_id, @transaction.reload.category_id
  end

  test "quick_update_category clears category when blank" do
    patch quick_update_category_workspace_transaction_path(@workspace, @transaction),
          params: { category_id: "" },
          headers: { "Accept" => "application/json" }

    assert_response :success
    assert_nil @transaction.reload.category_id
  end

  test "update with invalid params renders edit" do
    patch workspace_transaction_path(@workspace, @transaction), params: {
      transaction: { date: "", amount: "" }
    }
    assert_response :unprocessable_entity
  end

  test "reader cannot edit transaction" do
    sign_out @user
    sign_in users(:reader)
    get edit_workspace_transaction_path(@workspace, @transaction)
    assert_redirected_to workspace_path(@workspace)
  end

  test "reader cannot update transaction" do
    sign_out @user
    sign_in users(:reader)
    patch workspace_transaction_path(@workspace, @transaction), params: {
      transaction: { merchant: "Updated" }
    }
    assert_redirected_to workspace_path(@workspace)
  end

  test "reader cannot delete transaction" do
    sign_out @user
    sign_in users(:reader)
    delete workspace_transaction_path(@workspace, @transaction)
    assert_redirected_to workspace_path(@workspace)
    assert_not @transaction.reload.deleted
  end

  test "index without year filters" do
    get workspace_transactions_path(@workspace, year: nil, month: nil)
    assert_response :success
  end

  test "inline_update accepts negative amount for cancellations" do
    patch inline_update_workspace_transaction_path(@workspace, @transaction),
          params: { field: "amount", value: "-5000" },
          as: :json
    assert_response :success
    assert_equal(-5000, @transaction.reload.amount)
  end

  test "inline_update rejects zero amount" do
    patch inline_update_workspace_transaction_path(@workspace, @transaction),
          params: { field: "amount", value: "0" },
          as: :json
    assert_response :unprocessable_entity
  end

  test "inline_update rejects non-integer amount" do
    patch inline_update_workspace_transaction_path(@workspace, @transaction),
          params: { field: "amount", value: "abc" },
          as: :json
    assert_response :unprocessable_entity
  end

  # ADR-0007 §4: inline-edit이 merchant를 바꾸면 화면에 떠있던 학습 제안 row는
  # snapshot이 stale이 된다. 서버 stale 검증과 별도로, UX 차원에서 turbo response가
  # 그 row를 즉시 제거해야 한다 (Turbo remove는 미존재 id에 idempotent).
  test "inline_update turbo response removes stale category learning suggestion row" do
    patch inline_update_workspace_transaction_path(@workspace, @transaction),
          params: { field: "merchant", value: "새가맹점" },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_match(/turbo-stream action="remove"/, response.body)
    assert_match(/target="category-learning-suggestion-#{@transaction.id}"/, response.body)
  end

  test "update turbo response removes stale category learning suggestion row" do
    patch workspace_transaction_path(@workspace, @transaction),
          params: { transaction: { merchant: "새가맹점" } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_match(/turbo-stream action="remove"/, response.body)
    assert_match(/target="category-learning-suggestion-#{@transaction.id}"/, response.body)
  end

  # ADR-0011 §Decision 3: classification_source set 시점 검증.

  test "create with category_id sets classification_source to manual_set" do
    category = categories(:food)
    post workspace_transactions_path(@workspace),
         params: { transaction: { date: Date.current, merchant: "Test_ADR0011_A", amount: 1000, category_id: category.id } }

    tx = @workspace.transactions.where(merchant: "Test_ADR0011_A").last
    assert_equal "manual_set", tx.classification_source
  end

  test "create without category_id keeps classification_source nil" do
    post workspace_transactions_path(@workspace),
         params: { transaction: { date: Date.current, merchant: "Test_ADR0011_B", amount: 1000 } }

    tx = @workspace.transactions.where(merchant: "Test_ADR0011_B").last
    assert_nil tx.classification_source
  end

  test "quick_update_category sets classification_source to manual_set when category changes" do
    # 다른 카테고리로 변경 — same-category guard 회피 (Codex PR #174 fix).
    @transaction.update!(category: categories(:food), classification_source: nil)
    target = categories(:transport)

    patch quick_update_category_workspace_transaction_path(@workspace, @transaction),
          params: { category_id: target.id },
          as: :turbo_stream

    assert_response :success
    assert_equal "manual_set", @transaction.reload.classification_source
  end

  test "quick_update_category no-op re-click preserves classification_source" do
    # Codex PR #174 — dropdown은 현재 카테고리도 표시하므로 같은 카테고리 클릭은 no-op.
    # 기존 provenance(mapping_match 등)가 silent erase되면 안 된다.
    current_cat = categories(:food)
    @transaction.update!(category: current_cat, classification_source: "mapping_match")

    patch quick_update_category_workspace_transaction_path(@workspace, @transaction),
          params: { category_id: current_cat.id },
          as: :turbo_stream

    assert_response :success
    assert_equal "mapping_match", @transaction.reload.classification_source,
                 "no-op 클릭은 기존 provenance 보존"
  end

  test "update (edit page) routine non-category edit preserves classification_source" do
    # Codex PR #174 — edit 폼은 collection_select로 category_id를 항상 보내므로
    # merchant/amount/notes만 편집해도 manual_set으로 덮으면 안 된다.
    @transaction.update!(category: categories(:food), classification_source: "mapping_match")
    same_category_id = @transaction.category_id

    patch workspace_transaction_path(@workspace, @transaction),
          params: { transaction: { merchant: "노카테고리편집_가맹점", category_id: same_category_id } }

    assert_equal "mapping_match", @transaction.reload.classification_source,
                 "category 미변경 + 다른 필드만 편집 시 provenance 보존"
  end

  test "bulk_update change_category per-row guard preserves provenance on no-op rows" do
    # Codex PR #174: mixed selection — 일부는 이미 target 카테고리.
    # no-op rows의 provenance(mapping_match 등)는 보존돼야 한다.
    target = categories(:food)
    already_in_target = @workspace.transactions.create!(
      date: Date.current, amount: 1000, merchant: "BULK_NOOP",
      category: target, status: "committed",
      classification_source: "mapping_match"
    )
    changes_to_target = @workspace.transactions.create!(
      date: Date.current, amount: 2000, merchant: "BULK_CHANGE",
      category: categories(:transport), status: "committed",
      classification_source: "keyword_match"
    )

    post bulk_update_workspace_transactions_path(@workspace),
         params: {
           transaction_ids: "#{already_in_target.id},#{changes_to_target.id}",
           bulk_action: "change_category",
           category_id: target.id
         }

    assert_equal "mapping_match", already_in_target.reload.classification_source,
                 "no-op row 보존"
    assert_equal "manual_set", changes_to_target.reload.classification_source,
                 "실제 변동 row는 manual_set"
  end

  test "update (edit page) with category_id sets manual_set" do
    # Codex PR #174: TransactionsController#update가 누락되어 있어 edit 페이지에서
    # 사용자가 카테고리를 변경해도 stale provenance가 남는 문제.
    @transaction.update!(classification_source: "mapping_match")
    target = categories(:transport)

    patch workspace_transaction_path(@workspace, @transaction),
          params: { transaction: { category_id: target.id } }

    assert_equal "manual_set", @transaction.reload.classification_source
  end

  test "update (edit page) explicit clear (category_id='') sets source nil" do
    # Codex hotfix B: category=nil이면 classification_source도 nil이어야 한다.
    # 과거에는 manual_set으로 남아 category 없는 상태에 stale provenance가 붙었음.
    @transaction.update!(category: categories(:food), classification_source: "mapping_match")

    patch workspace_transaction_path(@workspace, @transaction),
          params: { transaction: { category_id: "" } }

    @transaction.reload
    assert_nil @transaction.category_id
    assert_nil @transaction.classification_source
  end

  # Codex hotfix B — classification_source semantics.

  test "quick_update_category clearing category sets source nil" do
    @transaction.update!(category: categories(:food), classification_source: "mapping_match")

    patch quick_update_category_workspace_transaction_path(@workspace, @transaction),
          params: { category_id: "" }, as: :json

    assert_response :success
    @transaction.reload
    assert_nil @transaction.category_id
    assert_nil @transaction.classification_source
  end

  test "bulk_update change_category with blank category_id is rejected" do
    tx = @workspace.transactions.create!(
      date: Date.current, amount: 1000, merchant: "BULK_BLANK",
      category: categories(:food), status: "committed",
      classification_source: "mapping_match"
    )

    post bulk_update_workspace_transactions_path(@workspace),
         params: { bulk_action: "change_category", category_id: "", transaction_ids: tx.id.to_s }

    assert_redirected_to workspace_transactions_path(@workspace)
    assert_match(/카테고리를 선택/, flash[:alert])
    # 카테고리/소스 변경 없음
    tx.reload
    assert_equal categories(:food).id, tx.category_id
    assert_equal "mapping_match", tx.classification_source
  end

  test "bulk_update change_category with invalid category_id is rejected (no silent clear)" do
    foreign = categories(:other_category)
    tx = @workspace.transactions.create!(
      date: Date.current, amount: 1000, merchant: "BULK_FOREIGN",
      category: categories(:food), status: "committed",
      classification_source: "mapping_match"
    )

    post bulk_update_workspace_transactions_path(@workspace),
         params: { bulk_action: "change_category", category_id: foreign.id, transaction_ids: tx.id.to_s }

    assert_redirected_to workspace_transactions_path(@workspace)
    assert_match(/유효하지 않은 카테고리/, flash[:alert])
    tx.reload
    assert_equal categories(:food).id, tx.category_id
    assert_equal "mapping_match", tx.classification_source
  end

  test "inline_update merchant change with no new mapping converts mapping_match to manual_set" do
    # Codex hotfix B: 핵심 의미 fix. merchant가 바뀌면 기존 mapping_match는 새
    # merchant와 무관한 stale provenance. 새 매핑이 없으면 manual_set으로 전환.
    @transaction.update!(merchant: "이전가맹점", category: categories(:food),
                         classification_source: "mapping_match")

    patch inline_update_workspace_transaction_path(@workspace, @transaction),
          params: { field: "merchant", value: "전혀새로운가맹점_NO_MAPPING" }, as: :json

    assert_response :success
    @transaction.reload
    assert_equal "전혀새로운가맹점_NO_MAPPING", @transaction.merchant
    assert_equal categories(:food).id, @transaction.category_id, "카테고리는 사용자 보존 의도로 유지"
    assert_equal "manual_set", @transaction.classification_source,
                 "새 merchant에 매핑이 없고 카테고리는 남았으므로 manual_set"
  end

  test "inline_update merchant change to merchant without mapping AND no category sets source nil" do
    @transaction.update!(merchant: "이전가맹점", category: nil, classification_source: nil)

    patch inline_update_workspace_transaction_path(@workspace, @transaction),
          params: { field: "merchant", value: "또다른가맹점_NO_MAPPING" }, as: :json

    assert_response :success
    @transaction.reload
    assert_nil @transaction.category_id
    assert_nil @transaction.classification_source
  end

  test "inline_update merchant change to merchant with mapping to same category refreshes source" do
    # Codex hotfix B: 새 merchant 기준 매핑이 결과적으로 같은 카테고리여도, 그
    # 매핑은 *새* merchant 기반이므로 source=mapping_match로 의미 갱신.
    target = categories(:food)
    CategoryMapping.create!(
      workspace: @workspace, merchant_pattern: "NEW_SAME_CAT_MERCHANT",
      match_type: "exact", source: "manual", category: target
    )
    @transaction.update!(merchant: "이전가맹점", category: target,
                         classification_source: "manual_set")

    patch inline_update_workspace_transaction_path(@workspace, @transaction),
          params: { field: "merchant", value: "NEW_SAME_CAT_MERCHANT" }, as: :json

    assert_response :success
    @transaction.reload
    assert_equal target.id, @transaction.category_id
    assert_equal "mapping_match", @transaction.classification_source,
                 "새 merchant 기준 매핑으로 갱신"
  end

  # Codex hotfix A: ledger row의 category-selector URL은 workspace-level
  # quick_update_category로 가야 한다. (review row는 session-scoped — reviews_controller_test 참조.)
  test "index category-selector URL is workspace-level quick_update_category" do
    get workspace_transactions_path(@workspace)
    assert_response :success
    expected = quick_update_category_workspace_transaction_path(@workspace, @transaction)
    assert_match(/data-category-selector-update-url-value="#{Regexp.escape(expected)}"/, response.body)
    assert_match(/data-category-selector-request-style-value="id"/, response.body)
  end

  test "inline_update merchant change with mapping hit sets mapping_match" do
    target = categories(:food)
    CategoryMapping.create!(
      workspace: @workspace,
      merchant_pattern: "재매칭가맹점_ADR0011",
      match_type: "exact",
      source: "manual",
      category: target
    )
    @transaction.update!(category: nil, classification_source: nil)

    patch inline_update_workspace_transaction_path(@workspace, @transaction),
          params: { field: "merchant", value: "재매칭가맹점_ADR0011" },
          as: :json

    assert_response :success
    @transaction.reload
    assert_equal target.id, @transaction.category_id
    assert_equal "mapping_match", @transaction.classification_source
  end

  # Phase 5 contrast 감사: transactions/index.html.erb 자체가 시맨틱 토큰만
  # 사용해야 한다 (ADR-0008). 본 테스트는 *view 파일의 source*를 직접 grep해서
  # 회귀를 잡는다.
  test "index view template uses semantic tokens (no hardcoded palette, no undefined tokens)" do
    src = File.read(Rails.root.join("app/views/transactions/index.html.erb"))
    %w[bg-indigo-600 text-gray-900 text-gray-500 text-gray-700 bg-white].each do |stale|
      assert_no_match(/\b#{Regexp.escape(stale)}\b/, src,
                      "transactions/index.html.erb에 옛 팔레트 #{stale}이 남아 있음")
    end
    # Codex PR #203 P2: 정의되지 않은 토큰(border-default/divide-default/text-action-strong)
    # 사용 금지.
    %w[border-default divide-default text-action-strong].each do |undef_token|
      assert_no_match(/\b#{Regexp.escape(undef_token)}\b/, src,
                      "transactions/index.html.erb에 정의되지 않은 토큰 #{undef_token} 사용")
    end
    assert_match(/\bbg-surface\b/, src)
    assert_match(/\btext-primary\b/, src)
    assert_match(/\bbg-action\b/, src)
  end
end
