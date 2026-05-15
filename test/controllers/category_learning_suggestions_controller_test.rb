require "test_helper"

# ADR-0007 §4: 인라인 카테고리 학습 제안 명시 수락 endpoint.
class CategoryLearningSuggestionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:admin)
    @workspace = workspaces(:main_workspace)
    @transaction = transactions(:food_transaction)
    sign_in @user
  end

  test "create requires admin access" do
    sign_out @user
    sign_in users(:member) # member_write
    refute users(:member).admin_of?(@workspace)

    assert_no_difference -> { CategoryMapping.count } do
      post workspace_transaction_category_learning_suggestion_path(@workspace, @transaction),
           params: { category_id: categories(:transport).id }
    end
    # require_workspace_admin_access redirects writers
    assert_response :redirect
  end

  test "create makes a manual exact mapping for the transaction merchant" do
    target = categories(:transport)
    @transaction.update!(merchant: "  스타벅스  ", category: target)

    assert_difference -> { CategoryMapping.count }, 1 do
      post workspace_transaction_category_learning_suggestion_path(@workspace, @transaction),
           params: { category_id: target.id },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    mapping = CategoryMapping.last
    assert_equal "스타벅스", mapping.merchant_pattern, "merchant must be stripped"
    assert_nil mapping.description_pattern
    assert_equal "exact", mapping.match_type
    assert_nil mapping.amount
    assert_equal "manual", mapping.source
    assert_equal target.id, mapping.category_id
    assert_equal @workspace.id, mapping.workspace_id
  end

  test "create rejects categories from a different workspace" do
    foreign = categories(:other_category)

    assert_no_difference -> { CategoryMapping.count } do
      post workspace_transaction_category_learning_suggestion_path(@workspace, @transaction),
           params: { category_id: foreign.id }
    end
    assert_response :unprocessable_entity
  end

  test "create is idempotent for the same merchant and category" do
    target = categories(:transport)
    @transaction.update!(category: target)

    assert_difference -> { CategoryMapping.count }, 1 do
      post workspace_transaction_category_learning_suggestion_path(@workspace, @transaction),
           params: { category_id: target.id },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    # Second call must not duplicate — dedup_signature uniqueness guards this.
    assert_no_difference -> { CategoryMapping.count } do
      post workspace_transaction_category_learning_suggestion_path(@workspace, @transaction),
           params: { category_id: target.id },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
  end

  test "create updates category when same signature mapping points elsewhere" do
    existing = CategoryMapping.create!(
      workspace: @workspace,
      merchant_pattern: @transaction.merchant.strip,
      description_pattern: nil,
      match_type: "exact",
      amount: nil,
      category: categories(:food),
      source: "manual"
    )
    new_target = categories(:transport)

    assert_no_difference -> { CategoryMapping.count } do
      post workspace_transaction_category_learning_suggestion_path(@workspace, @transaction),
           params: { category_id: new_target.id },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success
    assert_equal new_target.id, existing.reload.category_id
  end

  test "create rejects blank merchant" do
    @transaction.update_column(:merchant, "")

    assert_no_difference -> { CategoryMapping.count } do
      post workspace_transaction_category_learning_suggestion_path(@workspace, @transaction),
           params: { category_id: categories(:transport).id }
    end
    assert_response :unprocessable_entity
  end

  test "create reuses existing mapping when description_pattern is empty string" do
    # dedup_signature는 nil과 ""를 같은 키로 보지만 find_or_initialize_by(nil)은
    # ""를 못 찾아 unique constraint 충돌이 날 수 있다. find_default_exact_mapping
    # finder는 [nil, ""]를 함께 본다.
    existing = CategoryMapping.create!(
      workspace: @workspace,
      merchant_pattern: @transaction.merchant.strip,
      description_pattern: "",
      match_type: "exact",
      amount: nil,
      category: categories(:food),
      source: "manual"
    )
    new_target = categories(:transport)

    assert_no_difference -> { CategoryMapping.count } do
      post workspace_transaction_category_learning_suggestion_path(@workspace, @transaction),
           params: { category_id: new_target.id },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success
    assert_equal new_target.id, existing.reload.category_id
  end

  test "create recovers from a concurrent unique-constraint race" do
    # 시뮬레이션: 컨트롤러 첫 find_default_exact_mapping은 nil을 반환하지만,
    # save 직전에 다른 요청이 같은 signature row를 만들었다. mapping.save →
    # RecordNotUnique. 컨트롤러는 한 번 더 find & update하여 idempotent를
    # 보장해야 한다.
    target = categories(:transport)
    merchant = @transaction.merchant.strip
    racing_row = CategoryMapping.create!(
      workspace: @workspace,
      merchant_pattern: merchant,
      description_pattern: nil,
      match_type: "exact",
      amount: nil,
      category: categories(:food),
      source: "manual"
    )

    call_count = 0
    original = CategoryMapping.method(:find_default_exact_mapping)
    CategoryMapping.define_singleton_method(:find_default_exact_mapping) do |ws, m|
      call_count += 1
      # 첫 호출만 nil(처음에는 racing row가 없었다고 가정), 이후 호출은 실제 결과.
      call_count == 1 ? nil : original.call(ws, m)
    end

    begin
      assert_no_difference -> { CategoryMapping.count } do
        post workspace_transaction_category_learning_suggestion_path(@workspace, @transaction),
             params: { category_id: target.id },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
    ensure
      # `remove_method` 후 클래스 재로딩이 안 일어나면 후속 테스트에서 NoMethodError가
      # 난다. 원본 Method 객체로 다시 정의해 복원한다.
      CategoryMapping.define_singleton_method(:find_default_exact_mapping, original)
    end

    assert_response :success
    assert_equal target.id, racing_row.reload.category_id
    assert call_count >= 2, "rescue 경로가 finder를 재호출해야 함"
  end

  test "create response removes the suggestion row via turbo_stream" do
    target = categories(:transport)

    post workspace_transaction_category_learning_suggestion_path(@workspace, @transaction),
         params: { category_id: target.id },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_match(/turbo-stream action="remove"/, response.body)
    assert_match(/target="category-learning-suggestion-#{@transaction.id}"/, response.body)
  end
end
