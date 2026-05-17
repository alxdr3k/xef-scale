require "test_helper"

class MerchantRematchPolicyTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:main_workspace)
    @food = categories(:food)
    @transport = categories(:transport)
  end

  # Case 1: 새 매핑 hit & 다른 카테고리 — category/source 모두 갱신
  test "rematches to new mapping category and sets mapping_match" do
    CategoryMapping.create!(
      workspace: @workspace, merchant_pattern: "MR_REMATCH_DIFF",
      match_type: "exact", source: "manual", category: @transport
    )
    tx = @workspace.transactions.create!(
      date: Date.current, amount: 1000, merchant: "MR_REMATCH_DIFF",
      category: @food, classification_source: "manual_set"
    )

    MerchantRematchPolicy.apply!(@workspace, tx)
    tx.reload
    assert_equal @transport.id, tx.category_id
    assert_equal "mapping_match", tx.classification_source
  end

  # Case 2: 새 매핑 hit & 같은 카테고리 — source만 mapping_match로 갱신
  test "preserves category but updates source to mapping_match when rematch same category" do
    CategoryMapping.create!(
      workspace: @workspace, merchant_pattern: "MR_REMATCH_SAME",
      match_type: "exact", source: "manual", category: @food
    )
    tx = @workspace.transactions.create!(
      date: Date.current, amount: 1000, merchant: "MR_REMATCH_SAME",
      category: @food, classification_source: "manual_set"
    )

    MerchantRematchPolicy.apply!(@workspace, tx)
    tx.reload
    assert_equal @food.id, tx.category_id
    assert_equal "mapping_match", tx.classification_source,
                 "새 merchant 기준 매핑이 발견됐으므로 source는 mapping_match"
  end

  # Case 3: 매핑 없음 & 카테고리 present — manual_set
  test "promotes existing category to manual_set when no new mapping" do
    tx = @workspace.transactions.create!(
      date: Date.current, amount: 1000, merchant: "MR_NO_MAPPING_KEEP",
      category: @food, classification_source: "mapping_match"
    )

    MerchantRematchPolicy.apply!(@workspace, tx)
    tx.reload
    assert_equal @food.id, tx.category_id, "사용자 보존 카테고리는 유지"
    assert_equal "manual_set", tx.classification_source
  end

  # Case 4: 매핑 없음 & 카테고리 nil — source nil
  test "clears classification_source when no mapping and no category" do
    tx = @workspace.transactions.create!(
      date: Date.current, amount: 1000, merchant: "MR_NO_MAPPING_NIL",
      category: nil, classification_source: "keyword_match" # stale source
    )

    MerchantRematchPolicy.apply!(@workspace, tx)
    tx.reload
    assert_nil tx.category_id
    assert_nil tx.classification_source
  end

  # idempotency: source가 이미 정답이면 추가 update 발생 안 함 (no-op)
  test "no-op when source already matches policy outcome" do
    CategoryMapping.create!(
      workspace: @workspace, merchant_pattern: "MR_IDEMPOTENT",
      match_type: "exact", source: "manual", category: @food
    )
    tx = @workspace.transactions.create!(
      date: Date.current, amount: 1000, merchant: "MR_IDEMPOTENT",
      category: @food, classification_source: "mapping_match"
    )
    updated_at_before = tx.updated_at

    travel 1.second do
      MerchantRematchPolicy.apply!(@workspace, tx)
    end
    tx.reload
    assert_equal updated_at_before.to_i, tx.updated_at.to_i,
                 "변경 없으면 updated_at도 그대로 — no-op"
  end
end
