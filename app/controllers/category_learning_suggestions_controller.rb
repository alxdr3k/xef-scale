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
  def create
    category = @workspace.categories.find_by(id: params[:category_id])
    return head :unprocessable_entity if category.nil?

    merchant = @transaction.merchant.to_s.strip
    return head :unprocessable_entity if merchant.blank?

    mapping = CategoryMapping.find_or_initialize_by(
      workspace: @workspace,
      merchant_pattern: merchant,
      description_pattern: nil,
      match_type: "exact",
      amount: nil
    )
    mapping.category = category
    mapping.source = "manual"

    if mapping.save
      @mapping = mapping
      respond_to do |format|
        format.turbo_stream
      end
    else
      head :unprocessable_entity
    end
  end

  private

  def set_transaction
    @transaction = @workspace.transactions.find(params[:transaction_id])
  end
end
