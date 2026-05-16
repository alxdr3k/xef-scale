class CategoryLearningSuggestionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :require_workspace_admin_access
  before_action :set_transaction

  # POST /workspaces/:workspace_id/transactions/:transaction_id/category_learning_suggestion
  #
  # ADR-0007 §4 — explicit opt-in 학습. 사용자가 inline 카테고리 변경 후
  # "예, 자동 분류"를 클릭하면 본 endpoint로 POST. 서버는 @transaction에서
  # merchant를 derive해 CategoryMapping(source: "manual", match_type: "exact",
  # description_pattern: nil, amount: nil)을 idempotent하게 만든다.
  #
  # 동일 dedup signature가 다른 카테고리를 가리키면 category만 갱신한다.
  #
  # Stale snapshot 방어: 클라이언트는 suggestion 렌더 시점의 category_id, merchant
  # 스냅샷을 함께 보낸다. 그 사이 inline-edit으로 transaction의 category/merchant가
  # 바뀌었으면 snapshot이 현재 상태와 어긋나 422를 돌려보낸다. 사용자가 의도한
  # 매핑과 실제 만들 매핑이 일치하지 않는 stale 학습을 막는 안전장치이다.
  def create
    category = @workspace.categories.find_by(id: params[:category_id])
    return head :unprocessable_entity if category.nil?
    return head :unprocessable_entity if category.id != @transaction.category_id

    merchant = @transaction.merchant.to_s.strip
    return head :unprocessable_entity if merchant.blank?
    return head :unprocessable_entity if params[:merchant].to_s.strip != merchant

    mapping = upsert_default_mapping(merchant, category)
    if mapping
      @mapping = mapping
      respond_to do |format|
        format.turbo_stream
      end
    else
      head :unprocessable_entity
    end
  end

  private

  # dedup_signature 정합성 + race safety. 동일 (merchant, exact, blank desc,
  # nil amount) 매핑이 있으면 category만 갱신, 없으면 신규 생성. nil/""
  # description_pattern을 같은 축으로 본다.
  #
  # 동시 accept(더블 클릭, 두 admin 동시 작업 등) 사이 race가 unique index
  # (workspace_id, dedup_signature)를 때릴 수 있다. 두 가지 경로로 잡힐 수 있다:
  #   - Rails uniqueness validator(SELECT 후 INSERT 사이 race) → RecordInvalid
  #   - DB unique constraint → RecordNotUnique
  # 두 경우 모두 finder를 한 번 더 돌려 그 row를 update해 idempotent를 보장한다.
  def upsert_default_mapping(merchant, category)
    existing = CategoryMapping.find_default_exact_mapping(@workspace, merchant)
    return update_mapping(existing, category) if existing

    mapping = CategoryMapping.create!(
      workspace: @workspace,
      merchant_pattern: merchant,
      description_pattern: nil,
      match_type: "exact",
      amount: nil,
      category: category,
      source: "manual"
    )
    mapping
  rescue ActiveRecord::RecordInvalid => e
    # dedup uniqueness 외 검증 실패는 진짜 실패 — 그대로 422로 전달.
    raise unless e.record.errors[:dedup_signature].any?

    recover_from_race(merchant, category)
  rescue ActiveRecord::RecordNotUnique
    recover_from_race(merchant, category)
  end

  def recover_from_race(merchant, category)
    raced = CategoryMapping.find_default_exact_mapping(@workspace, merchant)
    raced ? update_mapping(raced, category) : nil
  end

  def update_mapping(mapping, category)
    mapping.update(category: category, source: "manual") ? mapping : nil
  end

  def set_transaction
    @transaction = @workspace.transactions.find(params[:transaction_id])
  end
end
