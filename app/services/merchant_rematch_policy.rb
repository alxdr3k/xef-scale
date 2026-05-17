class MerchantRematchPolicy
  # ADR-0011 §Decision 3 / Codex hotfix B 후속 — Reviews/Transactions 양쪽 inline
  # edit 경로가 merchant 변경 후 classification_source 재평가 정책을 동일하게
  # 적용한다. 두 controller 사이 helper 중복을 service로 흡수.
  #
  # 정책:
  #   1) 새 매핑 hit & 다른 카테고리: category·source 모두 mapping_match로 갱신
  #   2) 새 매핑 hit & 같은 카테고리: source만 mapping_match로 갱신 (새 merchant 기준의
  #      매핑이라는 사실 반영)
  #   3) 매핑 없음 & 카테고리 present: 사용자 보존 카테고리로 간주 → manual_set
  #   4) 매핑 없음 & 카테고리 nil: source nil (= 미분류)
  def self.apply!(workspace, transaction)
    new(workspace, transaction).apply!
  end

  def initialize(workspace, transaction)
    @workspace = workspace
    @transaction = transaction
  end

  def apply!
    new_category = CategoryMapping.find_category_for_merchant_and_description(
      @workspace, @transaction.merchant, @transaction.description
    )

    if new_category
      if @transaction.category_id != new_category.id
        @transaction.update(category: new_category, classification_source: "mapping_match")
      elsif @transaction.classification_source != "mapping_match"
        @transaction.update_column(:classification_source, "mapping_match")
      end
    elsif @transaction.category_id.present?
      if @transaction.classification_source != "manual_set"
        @transaction.update_column(:classification_source, "manual_set")
      end
    elsif @transaction.classification_source.present?
      @transaction.update_column(:classification_source, nil)
    end
  end
end
