class ReviewsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :require_workspace_access
  before_action :set_parsing_session
  before_action :require_workspace_write_access, except: [ :show ]

  def show
    @transactions = @parsing_session.reviewable_transactions
                                    .includes(:category, :financial_institution, :allowance_transaction)
    @pagy, @transactions = pagy(@transactions, items: 50)
    @categories = @workspace.categories.order(:name)
    @institutions = FinancialInstitution.all
    @read_only = @parsing_session.review_committed? || @parsing_session.review_rolled_back? || @parsing_session.review_discarded?
    @duplicate_confirmations = @parsing_session.duplicate_confirmations
                                               .pending
                                               .includes(
                                                 original_transaction: [ :financial_institution, :category ],
                                                 new_transaction: [ :financial_institution, :category ]
                                               )
                                               .order(:created_at)
  end

  def commit
    if @parsing_session.commit_all!(current_user)
      redirect_to review_workspace_parsing_session_path(@workspace, @parsing_session),
                  notice: "#{@parsing_session.transactions.committed.count}건의 거래가 확정되었습니다."
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
      count = transactions.count
      transactions.find_each(&:soft_delete!)
      notice = "#{count}건의 거래가 삭제되었습니다."
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
    permitted = [ :category_id, :notes, :description ]
    # Allow source change only if currently unknown
    permitted << :financial_institution_id if @transaction.source_editable?

    old_category_id = @transaction.category_id
    transaction_params = params.require(:transaction).permit(permitted)

    if @transaction.update(transaction_params)
      # 카테고리가 변경되었으면 매핑 생성
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

  def create_category_mapping(transaction, category)
    return if transaction.merchant.blank? || category.nil?

    # 이미 매핑이 있으면 업데이트, 없으면 생성
    mapping = CategoryMapping.find_or_initialize_by(
      workspace: @workspace,
      merchant_pattern: transaction.merchant
    )

    mapping.category = category
    mapping.source = "manual"
    mapping.save!
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn "[ReviewsController] 매핑 생성 실패: #{e.message}"
  end
end
