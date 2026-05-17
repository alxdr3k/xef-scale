class ReviewsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :require_workspace_access
  # ADR-0004 §"필수": 인덱스는 parsing_session_id를 가지지 않으므로
  # set_parsing_session에서 제외. 인덱스는 read 권한만 요구한다.
  before_action :set_parsing_session, except: [ :index ]
  before_action :require_workspace_write_access, except: [ :show, :index ]
  before_action :reject_if_finalized, only: [ :bulk_update, :bulk_resolve_duplicates, :update_transaction ]

  # 검토함 인덱스 — IA 1번 시민 (ADR-0004).
  # - 파싱 결과 탭: `ParsingSession.needs_review` (= completed.pending_review).
  #   `review_status: "pending_review"` 단독 사용 금지 (status가 pending/processing/failed인
  #   세션도 같은 값을 가질 수 있어 미처리 세션이 큐에 섞임 — ADR-0004 §"왜 needs_review인가").
  # - 중복 후보 탭: 같은 워크스페이스의 `needs_review` 세션에 속한 pending DuplicateConfirmation.
  #   DuplicateConfirmation은 자체 workspace_id가 없어 parsing_session 조인을 통해
  #   스코핑해야 cross-tenant leak이 방지된다 (ADR-0004 §"필수"). 또한 finalized(commit/
  #   rollback/discard) 세션의 잔여 pending dup은 사용자가 해결할 수 없으므로 인덱스에서
  #   제외한다.
  #
  # Counts:
  # - 탭 badge용 *전체* count는 `*_count` ivar로 보존, 실제 렌더 컬렉션은
  #   하드 limit으로 제한해 unbounded 응답 비용을 방지한다.
  # - 행별 (per-session) 거래/중복 카운트는 grouped count로 한 번에 집계해 N+1을 회피.
  # - 정식 per-tab pagy 도입은 Phase 3.3 검토함 화면 PR에서.
  INDEX_LIMIT = 50

  def index
    sessions_scope = @workspace.parsing_sessions.needs_review
    @pending_sessions_count = sessions_scope.count
    @pending_sessions = sessions_scope
                          .includes(:processed_file)
                          .order(created_at: :desc)
                          .limit(INDEX_LIMIT)

    duplicates_scope = DuplicateConfirmation
                         .pending
                         .joins(:parsing_session)
                         .merge(ParsingSession.needs_review)
                         .where(parsing_sessions: { workspace_id: @workspace.id })
    @pending_duplicates_count = duplicates_scope.count
    @pending_duplicates = duplicates_scope
                            .includes(
                              :parsing_session,
                              original_transaction: [ :category ],
                              new_transaction: [ :category ]
                            )
                            .order(created_at: :desc)
                            .limit(INDEX_LIMIT)

    session_ids = @pending_sessions.map(&:id)
    @pending_tx_counts = Transaction
                           .where(parsing_session_id: session_ids, status: "pending_review", deleted: false)
                           .group(:parsing_session_id)
                           .count
    @pending_dup_counts = DuplicateConfirmation
                            .where(parsing_session_id: session_ids, status: "pending")
                            .group(:parsing_session_id)
                            .count
  end

  def show
    @transactions = @parsing_session.reviewable_transactions
                                    .includes(:category, :allowance_transaction)
    @total_commit_count = @parsing_session.transactions.pending_review.where(deleted: false).count
    @pagy, @transactions = pagy(@transactions, limit: 50)
    @categories = @workspace.categories.order(:name)
    @read_only = @parsing_session.review_committed? || @parsing_session.review_rolled_back? || @parsing_session.review_discarded?
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
      check_budget_alerts
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
        # ADR-0011 §Decision 3 (Codex PR #174 follow-up): per-row 가드 — 실제 category
        # 변동시에만 manual_set 잠금. 이미 같은 카테고리인 rows는 provenance 보존.
        attrs = { category_id: category&.id }
        attrs[:classification_source] = "manual_set" if tx.category_id != category&.id
        tx.update!(attrs)
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
        # Capture user-driven field changes before system follow-ups overwrite
        # saved_changes (auto-categorization, classification_source update).
        record_review_event(@transaction.saved_changes.keys - [ "updated_at" ])

        # ADR-0011 §Decision 3 (Codex PR #174 follow-up): inline category_id 편집은
        # 실제 category가 *변동*했을 때만 manual_set으로 잠근다. 같은 값 재전송은
        # no-op이므로 기존 provenance(mapping_match 등) 보존.
        if field == "category_id" && @transaction.category_id != old_category_id
          @transaction.update_column(:classification_source, "manual_set")
        end

        # If merchant changed, try to auto-categorize
        if field == "merchant"
          new_category = CategoryMapping.find_category_for_merchant_and_description(
            @workspace,
            @transaction.merchant,
            @transaction.description
          )
          if new_category && new_category.id != old_category_id
            # ADR-0011 §Decision 3: merchant 변경으로 재매칭된 카테고리는 `mapping_match`.
            @transaction.update(category: new_category, classification_source: "mapping_match")
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

    # ADR-0011 §Decision 3: 폼에 `category_id` 키가 실제로 *포함되어 있는지*로
    # 사용자가 카테고리를 명시적으로 다뤘는지 판단한다. 빈 문자열로 *해제*한
    # 경우도 사용자 의도이므로 `present?` 검사는 부적절 — 키 존재로 본다.
    category_id_submitted = params[:transaction].respond_to?(:key?) &&
                            params[:transaction].key?(:category_id)

    if @transaction.update(transaction_params)
      # Capture user-driven field changes before system follow-ups overwrite
      # saved_changes (classification_source, auto re-categorization).
      record_review_event(@transaction.saved_changes.keys - [ "updated_at" ])

      # ADR-0011 §Decision 3 (Codex PR #174 follow-up): 검토 폼도 collection_select로
      # category_id를 항상 보낼 수 있으므로 키 존재만으로는 부족. 실제 category_id가
      # *변동*한 경우에만 manual_set 잠금 — 동일 카테고리는 기존 provenance 보존.
      if category_id_submitted && @transaction.category_id != old_category_id
        @transaction.update_column(:classification_source, "manual_set")
      end

      # ADR-0011 §Decision 3 (Codex PR #174 follow-up): merchant 변경 + 결과적으로
      # 카테고리가 nil(미분류)일 때 자동 재매칭. 단 사용자가 이번 요청에서
      # *명시적으로 해제*한 경우(`category_intentionally_cleared`)는 그 의도를
      # 존중해 rematch 금지.
      merchant_changed = old_merchant != @transaction.merchant
      category_intentionally_cleared = category_id_submitted &&
                                       old_category_id.present? &&
                                       @transaction.category_id.blank?

      if merchant_changed && @transaction.category_id.blank? && !category_intentionally_cleared
        new_category = CategoryMapping.find_category_for_merchant_and_description(
          @workspace,
          @transaction.merchant,
          @transaction.description
        )
        # ADR-0011 §Decision 3: 재매칭이 *다른* 카테고리를 가리킬 때만 mapping_match로
        # 갱신한다. 같은 카테고리면 의미상 분류 변동이 없으므로 기존 classification_source
        # (예: 사용자가 이전에 지정한 manual_set)를 silent overwrite하지 않는다.
        if new_category && new_category.id != @transaction.category_id
          @transaction.update(category: new_category, classification_source: "mapping_match")
        end
      end

      # ADR-0007 §4: 카테고리 변경 시 묵시적 CategoryMapping 생성은 금지.
      # 학습은 CategoryLearningSuggestionsController explicit opt-in으로만 가능하다.

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

  # Records the user-driven field changes that landed on @transaction. Skips
  # if nothing changed (no-op submit) so we don't pollute the metric.
  def record_review_event(changed_fields)
    return if changed_fields.blank?

    ImportReviewEventRecorder.record(
      workspace: @workspace,
      parsing_session: @parsing_session,
      reviewed_transaction: @transaction,
      event_type: "transaction_updated",
      changed_fields: changed_fields
    )
  end

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

  def check_budget_alerts
    budget = @workspace.budget
    return unless budget

    # 이번 커밋으로 확정된 거래의 월들을 수집
    committed_transactions = @parsing_session.transactions.where(status: "committed")
    affected_months = committed_transactions
      .pluck(:date)
      .map { |d| [ d.year, d.month ] }
      .uniq

    # fallback: 커밋된 거래가 없으면 현재 월만 확인
    affected_months = [ [ Date.current.year, Date.current.month ] ] if affected_months.empty?

    affected_months.each do |year, month|
      check_budget_alert_for_month(year, month)
    end
  end

  def check_budget_alert_for_month(year, month)
    budget = @workspace.budget
    return unless budget

    progress = budget.progress_for_month(year, month)
    alert_type = if progress[:percentage] >= 100
      "budget_exceeded"
    elsif progress[:percentage] >= 80
      "budget_warning"
    end
    return unless alert_type

    @workspace.members.find_each do |member|
      already_alerted = Notification.where(
        workspace: @workspace, user: member, notification_type: alert_type,
        target_year: year, target_month: month
      ).exists?

      next if already_alerted
      Notification.create_budget_alert!(@workspace, member, alert_type, progress, year: year, month: month)
    end
  end
end
