class ReviewsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :require_workspace_access
  before_action :set_parsing_session
  before_action :require_workspace_write_access, except: [ :show ]
  before_action :reject_if_finalized, only: [ :bulk_update, :bulk_resolve_duplicates, :update_transaction ]

  def show
    @transactions = @parsing_session.reviewable_transactions
                                    .includes(:category, :allowance_transaction)
    @total_commit_count = @parsing_session.transactions.pending_review.where(deleted: false).count
    @pagy, @transactions = pagy(@transactions, limit: 50)
    @categories = @workspace.categories.order(:name)
    @read_only = @parsing_session.review_committed? || @parsing_session.review_rolled_back? || @parsing_session.review_discarded?
    @import_issues = @parsing_session.open_import_issues.to_a
    @duplicate_confirmations = @parsing_session.duplicate_confirmations
                                               .pending
                                               .includes(
                                                 original_transaction: [ :category, :parsing_session ],
                                                 new_transaction: [ :category ]
                                               )
                                               .order(:created_at)
  end

  def commit
    if @parsing_session.has_unresolved_duplicates?
      redirect_to review_workspace_parsing_session_path(@workspace, @parsing_session),
                  alert: "중복으로 의심되는 거래가 남아 있습니다. 먼저 처리해 주세요."
      return
    end

    if @parsing_session.commit_all!(current_user)
      BudgetAlertService.create_for_transactions!(
        @workspace,
        @parsing_session.transactions.where(status: "committed")
      )
      summary = @parsing_session.commit_summary
      parts = [ "#{summary[:committed]}건의 거래가 확정되었습니다." ]
      parts << "#{summary[:excluded]}건은 제외되었습니다." if summary[:excluded].positive?
      parts << "중복 #{summary[:originals_kept]}건은 기존 거래만 남겼습니다." if summary[:originals_kept].positive?
      parts << "분류 필요 #{summary[:uncategorized]}건." if summary[:uncategorized].positive?
      redirect_to review_workspace_parsing_session_path(@workspace, @parsing_session),
                  notice: parts.join(" ")
    else
      redirect_to review_workspace_parsing_session_path(@workspace, @parsing_session),
                  alert: "거래 확정에 실패했습니다."
    end
  end

  def rollback
    if @parsing_session.rollback_all!(current_user)
      redirect_to workspace_parsing_sessions_path(@workspace),
                  notice: "모든 거래가 롤백되었습니다."
    else
      redirect_to review_workspace_parsing_session_path(@workspace, @parsing_session),
                  alert: "롤백에 실패했습니다."
    end
  end

  def discard
    if @parsing_session.discard_all!
      redirect_to workspace_parsing_sessions_path(@workspace),
                  notice: "업로드가 취소되었습니다."
    else
      redirect_to review_workspace_parsing_session_path(@workspace, @parsing_session),
                  alert: "취소에 실패했습니다."
    end
  end

  def bulk_resolve_duplicates
    decision = params[:decision]
    pending_confirmations = @parsing_session.duplicate_confirmations.pending

    resolved_count = 0
    pending_confirmations.find_each do |confirmation|
      confirmation.resolve!(decision)
      resolved_count += 1
    end

    respond_to do |format|
      format.html do
        redirect_to review_workspace_parsing_session_path(@workspace, @parsing_session),
                    notice: "#{resolved_count}건의 중복 거래가 처리되었습니다."
      end
      format.turbo_stream do
        flash.now[:notice] = "#{resolved_count}건의 중복 거래가 처리되었습니다."
      end
    end
  rescue ArgumentError => e
    redirect_to review_workspace_parsing_session_path(@workspace, @parsing_session),
                alert: e.message
  end

  def bulk_update
    transaction_ids = params[:transaction_ids].to_s.split(",").map(&:to_i)
    action = params[:bulk_action]

    transactions = @parsing_session.transactions.where(id: transaction_ids)

    case action
    when "delete"
      count = 0
      transactions.find_each do |tx|
        if tx.pending_review?
          tx.rollback!
          count += 1
        end
      end
      notice = "#{count}건의 거래가 이번 가져오기에서 제외되었습니다."
    when "mark_allowance"
      count = 0
      transactions.find_each do |tx|
        unless tx.allowance?
          AllowanceTransaction.create!(expense_transaction: tx, user: current_user)
          count += 1
        end
      end
      notice = "#{count}건의 거래가 용돈으로 표시되었습니다."
    when "unmark_allowance"
      count = 0
      transactions.find_each do |tx|
        if tx.allowance?
          tx.allowance_transaction.destroy!
          count += 1
        end
      end
      notice = "#{count}건의 거래가 용돈에서 해제되었습니다."
    when "change_category"
      category = @workspace.categories.find_by(id: params[:category_id])
      count = 0
      transactions.find_each do |tx|
        tx.update!(category_id: category&.id)
        create_category_mapping(tx, category) if category
        count += 1
      end
      notice = "#{count}건의 거래 카테고리가 변경되었습니다."
    else
      notice = "알 수 없는 작업입니다."
    end

    respond_to do |format|
      format.html { redirect_to review_workspace_parsing_session_path(@workspace, @parsing_session), notice: notice }
      format.turbo_stream { flash.now[:notice] = notice }
    end
  end

  def update_transaction
    @transaction = @parsing_session.transactions.find(params[:transaction_id])

    # Only allow editing specific fields
    permitted = [ :category_id, :notes, :merchant, :date, :amount, :payment_type, :installment_month, :installment_total ]

    old_category_id = @transaction.category_id
    old_merchant = @transaction.merchant

    # Handle inline editing (single field updates via JSON)
    if params[:field].present? && params[:transaction].blank?
      field = params[:field]
      value = params[:value]

      # Validate field is allowed
      unless permitted.map(&:to_s).include?(field)
        head :unprocessable_entity
        return
      end

      # Convert and validate value
      case field
      when "amount"
        value = Integer(value, exception: false)
        if value.nil? || value == 0
          head :unprocessable_entity
          return
        end
      when "date"
        begin
          value = Date.parse(value)
        rescue ArgumentError, TypeError
          head :unprocessable_entity
          return
        end
      when "category_id"
        if value.present? && !@workspace.categories.exists?(value)
          head :unprocessable_entity
          return
        end
      end

      if @transaction.update(field => value)
        # If merchant changed, try to auto-categorize
        if field == "merchant"
          new_category = CategoryMapping.find_category_for_merchant_and_description(
            @workspace,
            @transaction.merchant,
            @transaction.description
          )
          if new_category && new_category.id != old_category_id
            @transaction.update(category: new_category)
          end
        end

        respond_to do |format|
          format.html { redirect_to review_workspace_parsing_session_path(@workspace, @parsing_session), notice: "거래가 수정되었습니다." }
          format.turbo_stream { flash.now[:notice] = "거래가 수정되었습니다." }
        end
        return
      else
        head :unprocessable_entity
        return
      end
    end

    # Handle form-based updates (original behavior)
    transaction_params = params.require(:transaction).permit(permitted)

    if @transaction.update(transaction_params)
      # merchant가 변경되었고, 사용자가 직접 카테고리를 변경하지 않았으면 재매칭
      merchant_changed = old_merchant != @transaction.merchant
      category_not_manually_changed = transaction_params[:category_id].blank?

      if merchant_changed && category_not_manually_changed
        new_category = CategoryMapping.find_category_for_merchant_and_description(
          @workspace,
          @transaction.merchant,
          @transaction.description
        )
        @transaction.update(category: new_category) if new_category
      end

      # 카테고리가 수동으로 변경되었으면 매핑 생성
      if transaction_params[:category_id].present? && transaction_params[:category_id].to_i != old_category_id
        create_category_mapping(@transaction, @transaction.category)
      end

      respond_to do |format|
        format.html { redirect_to review_workspace_parsing_session_path(@workspace, @parsing_session), notice: "거래가 수정되었습니다." }
        format.turbo_stream { flash.now[:notice] = "거래가 수정되었습니다." }
      end
    else
      respond_to do |format|
        format.html { redirect_to review_workspace_parsing_session_path(@workspace, @parsing_session), alert: "수정에 실패했습니다." }
        format.turbo_stream { render :update_transaction_error }
      end
    end
  end

  private

  def set_workspace
    @workspace = current_user.workspaces.find(params[:workspace_id])
  end

  def set_parsing_session
    @parsing_session = @workspace.parsing_sessions.find(params[:parsing_session_id] || params[:id])
  end

  def require_workspace_access
    unless current_user.can_read?(@workspace)
      redirect_to root_path, alert: "접근 권한이 없습니다."
    end
  end

  def require_workspace_write_access
    unless current_user.can_write?(@workspace)
      redirect_to root_path, alert: "수정 권한이 없습니다."
    end
  end

  # Once a parsing session has been committed / rolled back / discarded, the
  # import workflow is frozen. Block bulk edits and inline edits here so the
  # guard doesn't depend on action-specific checks.
  def reject_if_finalized
    return if @parsing_session.review_pending?

    respond_to do |format|
      format.turbo_stream { head :forbidden }
      format.json { head :forbidden }
      format.html do
        redirect_to review_workspace_parsing_session_path(@workspace, @parsing_session),
                    alert: "이미 종료된 세션은 수정할 수 없습니다."
      end
    end
  end

  def create_category_mapping(transaction, category)
    return if transaction.merchant.blank? || category.nil?

    # description이 있으면 description_pattern 포함 매핑 생성, 없으면 기본 매핑
    description_pattern = extract_description_pattern(transaction.description)

    mapping = CategoryMapping.find_or_initialize_by(
      workspace: @workspace,
      merchant_pattern: transaction.merchant,
      description_pattern: description_pattern,
      match_type: "exact",
      amount: nil
    )

    mapping.category = category
    mapping.source = "manual"
    mapping.save!
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn "[ReviewsController] 매핑 생성 실패: #{e.message}"
  end

  def extract_description_pattern(description)
    return nil if description.blank?

    description.strip.presence
  end
end
