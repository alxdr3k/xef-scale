class TransactionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :require_workspace_access
  before_action :set_transaction, only: [ :show, :edit, :update, :destroy, :toggle_allowance, :quick_update_category, :inline_update ]
  before_action :set_transaction_including_deleted, only: [ :restore ]
  before_action :require_workspace_write_access, only: [ :new, :create, :edit, :update, :destroy, :quick_update_category, :inline_update, :bulk_update, :restore ]

  def index
    @year = sanitize_year(params[:year]) || Date.current.year
    @month = sanitize_month(params[:month])

    transactions = @workspace.transactions.active.excluding_allowance.includes(:category, parsing_session: :processed_file)
    transactions = apply_index_filters(transactions, year: @year, month: @month)
    transactions = transactions.order(date: :desc, created_at: :desc)

    @pagy, @transactions = pagy(transactions, limit: 50)

    # Stats
    @total_amount = transactions.excluding_coupon.sum(:amount)
    @categories = @workspace.categories.order(:name)

    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  def show
  end

  def new
    @transaction = @workspace.transactions.build(date: Date.current)
    @categories = @workspace.categories
  end

  def create
    @transaction = @workspace.transactions.build(transaction_params)
    @transaction.source_type ||= "manual"
    # ADR-0011 §Decision 3: 직접 입력 시 카테고리가 지정되면 사용자 명시 →
    # `manual_set`. 카테고리 미지정은 nil 유지 (chip 마크 없음).
    @transaction.classification_source = "manual_set" if @transaction.category_id.present?

    if @transaction.save
      @categories = @workspace.categories.order(:name)
      respond_to do |format|
        format.html { redirect_to workspace_transactions_path(@workspace), notice: "거래가 추가되었습니다." }
        format.turbo_stream { flash[:notice] = "거래가 추가되었습니다." }
      end
    else
      @categories = @workspace.categories
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @categories = @workspace.categories
  end

  def update
    old_allowance_status = @transaction.allowance?
    old_category_id = @transaction.category_id
    # ADR-0011 §Decision 3: 폼에 `category_id` 키가 포함됐는지로 판단.
    # 빈 문자열로 해제한 경우도 사용자 명시 행위.
    category_id_submitted = params[:transaction].respond_to?(:key?) &&
                            params[:transaction].key?(:category_id)

    if @transaction.update(transaction_params)
      # ADR-0011 §Decision 3 (Codex hotfix B): 실제 category_id가 *변동*한
      # 경우에만 provenance를 갱신.
      #   - 새 category_id present → manual_set
      #   - 새 category_id nil (clear) → nil (category가 없으면 source 의미도 없음)
      #   - 동일 카테고리 재전송 → 기존 provenance 보존
      if category_id_submitted && @transaction.category_id != old_category_id
        new_source = @transaction.category_id.present? ? "manual_set" : nil
        @transaction.update_column(:classification_source, new_source)
      end

      # Handle allowance toggle if present in params
      if params[:allowance].present?
        new_allowance_status = params[:allowance] == "1"
        if new_allowance_status != old_allowance_status
          if new_allowance_status
            AllowanceTransaction.mark_as_allowance!(@transaction, current_user)
          else
            AllowanceTransaction.unmark_as_allowance!(@transaction, current_user)
          end
          # Reload to get updated allowance status
          @transaction = @workspace.transactions
                                   .includes(:allowance_transaction, :category)
                                   .find(@transaction.id)
        end
      end

      @categories = @workspace.categories.order(:name)
      respond_to do |format|
        format.html { redirect_to params[:return_to].presence || workspace_transactions_path(@workspace), notice: "거래가 수정되었습니다." }
        format.turbo_stream { flash[:notice] = "거래가 수정되었습니다." }
      end
    else
      @categories = @workspace.categories
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @transaction.soft_delete!

    respond_to do |format|
      format.html { redirect_to workspace_transactions_path(@workspace), notice: "거래가 삭제되었습니다." }
      format.turbo_stream { flash.now[:notice] = "거래가 삭제되었습니다." }
    end
  end

  def toggle_allowance
    if @transaction.allowance?
      AllowanceTransaction.unmark_as_allowance!(@transaction, current_user)
      notice = "용돈에서 제외되었습니다."
    else
      AllowanceTransaction.mark_as_allowance!(@transaction, current_user)
      notice = "용돈으로 표시되었습니다."
    end

    # 변경된 상태 반영을 위해 reload (association 캐시 포함)
    @transaction = @workspace.transactions
                             .includes(:allowance_transaction, :category)
                             .find(@transaction.id)

    # turbo_stream 응답을 위한 변수 설정
    @categories = @workspace.categories.order(:name)
    @source = params[:source]
    if @source == "review"
      @parsing_session = @workspace.parsing_sessions.find(params[:parsing_session_id])
      @read_only = false
    end

    respond_to do |format|
      format.html { redirect_to workspace_transactions_path(@workspace), notice: notice }
      format.turbo_stream { flash.now[:notice] = notice }
    end
  end

  def quick_update_category
    category_id = params[:category_id].presence
    old_category_id = @transaction.category_id

    if category_id.present? && !@workspace.categories.exists?(id: category_id)
      respond_to do |format|
        format.turbo_stream { head :unprocessable_entity }
        format.json do
          render json: { success: false, errors: [ "다른 워크스페이스의 카테고리는 사용할 수 없습니다." ] },
                 status: :unprocessable_entity
        end
      end
      return
    end

    # ADR-0011 §Decision 3 (Codex hotfix B): dropdown은 현재 카테고리도
    # 표시하므로 같은 카테고리 재클릭은 no-op. category가 실제로 *변동*했을 때만
    # provenance 갱신. 카테고리가 nil로 변하면 source도 nil — 미분류 상태에
    # manual_set이 남으면 의미 오염.
    category_changed = category_id.to_s.presence != old_category_id&.to_s
    update_attrs = { category_id: category_id }
    if category_changed
      update_attrs[:classification_source] = category_id.present? ? "manual_set" : nil
    end

    if @transaction.update(update_attrs)
      @categories = @workspace.categories.order(:name)
      @show_learning_suggestion = eligible_for_learning_suggestion?(@transaction, old_category_id)

      respond_to do |format|
        format.turbo_stream
        format.json { render json: { success: true } }
      end
    else
      respond_to do |format|
        format.turbo_stream { head :unprocessable_entity }
        format.json do
          render json: { success: false, errors: @transaction.errors.full_messages },
                 status: :unprocessable_entity
        end
      end
    end
  end

  def inline_update
    # Handle form-based updates (e.g., payment_type selector)
    if params[:transaction].present?
      permitted = %i[date merchant amount notes payment_type installment_month installment_total]
      if @transaction.update(params.require(:transaction).permit(permitted))
        @categories = @workspace.categories.order(:name)
        respond_to do |format|
          format.turbo_stream
        end
      else
        head :unprocessable_entity
      end
      return
    end

    # Handle inline-edit JSON updates (field/value params)
    field = params[:field]
    value = params[:value]

    # Validate field is allowed
    allowed_fields = %w[date merchant amount notes]
    unless allowed_fields.include?(field)
      head :unprocessable_entity
      return
    end

    # Convert and validate value
    case field
    when "amount"
      # Cancellations/refunds are stored as negative integers (AiTextParser
      # marks 승인취소/환불 with is_cancel: true and flips the sign). Inline
      # edits must accept negatives to stay consistent; only zero and
      # non-integer input are rejected here.
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
    end

    old_category_id = @transaction.category_id

    if @transaction.update(field => value)
      # ADR-0011 §Decision 3 (Codex hotfix B): merchant가 바뀌면 새 merchant 기준
      # provenance 재평가가 필수다. 과거 코드는 새 매핑이 *다른* 카테고리를 가리킬
      # 때만 갱신했는데, 그 경우 기존 mapping_match가 새 merchant와는 무관한
      # 매핑인데도 그대로 남아 stale provenance가 됐다.
      apply_merchant_rematch_policy!(@transaction) if field == "merchant"

      @categories = @workspace.categories.order(:name)
      respond_to do |format|
        format.turbo_stream
        format.json { render json: { success: true, value: @transaction.send(field) } }
      end
    else
      head :unprocessable_entity
    end
  end

  def bulk_update
    transaction_ids = params[:transaction_ids].to_s.split(",").map(&:to_i).reject(&:zero?)

    if transaction_ids.empty?
      redirect_to workspace_transactions_path(@workspace), alert: "선택된 항목이 없습니다."
      return
    end

    action = params[:bulk_action]
    transactions = @workspace.transactions.active.where(id: transaction_ids)

    case action
    when "delete"
      count = transactions.count
      transactions.find_each(&:soft_delete!)
      notice = "#{count}건의 거래가 삭제되었습니다."
    when "mark_allowance"
      count = 0
      transactions.find_each do |tx|
        unless tx.allowance?
          AllowanceTransaction.mark_as_allowance!(tx, current_user)
          count += 1
        end
      end
      notice = "#{count}건의 거래가 용돈으로 표시되었습니다."
    when "unmark_allowance"
      count = 0
      transactions.find_each do |tx|
        if tx.allowance?
          AllowanceTransaction.unmark_as_allowance!(tx, current_user)
          count += 1
        end
      end
      notice = "#{count}건의 거래가 용돈에서 해제되었습니다."
    when "change_category"
      # Codex hotfix B: invalid/blank category_id를 nil clear로 silent 해석하지
      # 않는다 — bulk action은 파괴 범위가 크므로 422/alert로 막는다. 단건
      # quick_update_category와 contract를 맞춤.
      if params[:category_id].blank?
        redirect_to workspace_transactions_path(@workspace),
                    alert: "카테고리를 선택해 주세요."
        return
      end
      category = @workspace.categories.find_by(id: params[:category_id])
      unless category
        redirect_to workspace_transactions_path(@workspace),
                    alert: "유효하지 않은 카테고리입니다."
        return
      end
      count = 0
      transactions.find_each do |tx|
        # ADR-0011 §Decision 3: per-row 가드 — 실제 category 변동시에만 manual_set.
        # mixed selection에서 이미 같은 카테고리인 rows는 기존 provenance 보존.
        attrs = { category_id: category.id }
        attrs[:classification_source] = "manual_set" if tx.category_id != category.id
        tx.update!(attrs)
        count += 1
      end
      notice = "#{count}건의 거래 카테고리가 변경되었습니다."
    else
      notice = "알 수 없는 작업입니다."
    end

    redirect_to workspace_transactions_path(@workspace), notice: notice
  end

  def suggest_category
    merchant = params[:merchant].to_s.strip
    description = params[:description].to_s.strip.presence

    category = CategoryMapping.find_category_for_merchant_and_description(@workspace, merchant, description)

    render json: { category_id: category&.id }
  end

  def export
    year = sanitize_year(params[:year])
    month = sanitize_month(params[:month])

    transactions = @workspace.transactions.active.excluding_allowance.includes(:category, parsing_session: :processed_file)
    transactions = apply_index_filters(transactions, year: year, month: month)

    respond_to do |format|
      format.csv do
        send_data generate_csv(transactions),
                  filename: "transactions_#{Date.current}.csv",
                  type: "text/csv; charset=utf-8"
      end
    end
  end

  def duplicates
    transactions = @workspace.transactions.active.includes(:category, parsing_session: :processed_file)
                            .with_duplicates
                            .order(date: :desc, amount: :desc, created_at: :desc)

    duplicate_groups = transactions.group_by { |t| [ t.date, t.amount ] }
                                   .values
                                   .select { |group| group.size >= 2 }

    pairs = []
    duplicate_groups.each do |group|
      group.combination(2).each do |left, right|
        pairs << {
          left: serialize_transaction(left),
          right: serialize_transaction(right)
        }
      end
    end

    categories = @workspace.categories.order(:name).map { |c| { id: c.id, name: c.name, color: c.color } }

    render json: {
      pairs: pairs,
      total: pairs.size,
      categories: categories
    }
  end

  def restore
    @transaction.restore!

    respond_to do |format|
      format.json { render json: { success: true } }
    end
  end

  private

  def set_transaction
    @transaction = @workspace.transactions.find(params[:id])
  end

  def set_transaction_including_deleted
    @transaction = @workspace.transactions.unscoped.where(workspace: @workspace).find(params[:id])
  end

  def serialize_transaction(transaction)
    {
      id: transaction.id,
      date: transaction.formatted_date,
      merchant: transaction.merchant,
      amount: transaction.amount,
      formatted_amount: transaction.formatted_amount,
      category: transaction.category&.name,
      category_id: transaction.category_id,
      notes: transaction.notes,
      created_at: transaction.created_at.strftime("%m/%d %H:%M"),
      delete_url: workspace_transaction_path(@workspace, transaction),
      restore_url: restore_workspace_transaction_path(@workspace, transaction),
      category_url: quick_update_category_workspace_transaction_path(@workspace, transaction)
    }
  end

  def transaction_params
    params.require(:transaction).permit(
      :date, :merchant, :amount, :notes,
      :category_id, :payment_type,
      :installment_month, :installment_total
    )
  end

  def generate_csv(transactions)
    require "csv"
    CSV.generate(headers: true, encoding: "UTF-8") do |csv|
      csv << [ "날짜", "내역", "금액", "분류", "메모" ]
      transactions.order(date: :desc).each do |tx|
        csv << [
          tx.formatted_date,
          csv_safe(tx.merchant),
          tx.amount,
          csv_safe(tx.category&.name),
          csv_safe(tx.notes)
        ]
      end
    end
  end

  def csv_safe(value)
    str = value.to_s
    str.start_with?("=", "+", "-", "@", "\t", "\r") ? "'#{str}" : str
  end

  # ADR-0011 §Decision 3 (Codex hotfix B): merchant가 바뀌면 새 merchant 기준
  # provenance를 *반드시* 재평가한다. 과거 코드는 "새 매핑이 있고 그것이 *다른*
  # 카테고리"일 때만 갱신했는데, 그 경우:
  #   - 새 merchant에 대한 매핑이 없고 기존 카테고리만 남은 케이스 → 기존
  #     classification_source(mapping_match/keyword_match/gemini_batch)가 새
  #     merchant와는 무관한 stale provenance로 남는다.
  #   - 새 매핑이 같은 카테고리로 끝난 경우도 source는 *새* merchant 기준의
  #     매핑이라는 사실을 반영해 mapping_match로 갱신해야 의미가 일치한다.
  #
  # 정책:
  #   1) 새 매핑 hit & 다른 카테고리: category·source 모두 mapping_match로 갱신
  #   2) 새 매핑 hit & 같은 카테고리: source만 mapping_match로 갱신
  #   3) 매핑 없음 & 카테고리 present: 사용자 보존 카테고리로 간주 → manual_set
  #   4) 매핑 없음 & 카테고리 nil: source nil
  def apply_merchant_rematch_policy!(transaction)
    new_category = CategoryMapping.find_category_for_merchant_and_description(
      @workspace, transaction.merchant, transaction.description
    )

    if new_category
      if transaction.category_id != new_category.id
        transaction.update(category: new_category, classification_source: "mapping_match")
      elsif transaction.classification_source != "mapping_match"
        transaction.update_column(:classification_source, "mapping_match")
      end
    elsif transaction.category_id.present?
      transaction.update_column(:classification_source, "manual_set") if transaction.classification_source != "manual_set"
    else
      transaction.update_column(:classification_source, nil) if transaction.classification_source.present?
    end
  end

  # ADR-0007 §4: 카테고리 변경 시 학습은 explicit opt-in으로만 일어난다.
  # 사용자가 quick_update_category로 행 카테고리를 바꿨을 때 inline
  # suggestion row를 띄울지 결정한다.
  #
  # 조건:
  #   - admin 권한
  #   - 카테고리가 실제로 변경되었고 새 카테고리가 present
  #   - merchant가 present (학습 대상)
  #   - 동일 (merchant, exact, amount=nil, description=nil) signature 매핑이
  #     이미 같은 카테고리를 가리키면 학습할 게 없으므로 미노출
  def eligible_for_learning_suggestion?(transaction, old_category_id)
    return false unless current_user.admin_of?(@workspace)
    return false if transaction.category_id.blank?
    return false if transaction.category_id == old_category_id
    return false if transaction.merchant.to_s.strip.blank?

    existing = CategoryMapping.find_default_exact_mapping(@workspace, transaction.merchant)
    existing.nil? || existing.category_id != transaction.category_id
  end

  def apply_index_filters(scope, year:, month:)
    scope = scope.for_year(year) if year && month.nil?
    scope = scope.for_month(year, month) if year && month.present?
    scope = scope.by_category(params[:category_id]) if params[:category_id].present?
    scope = scope.search(params[:q]) if params[:q].present?
    scope = scope.where(category_id: nil) if params[:filter] == "uncategorized"
    scope
  end

  def sanitize_year(value)
    return nil if value.blank?
    year = Integer(value.to_s, exception: false)
    return nil unless year
    return nil unless year.between?(2000, 2100)
    year
  end

  def sanitize_month(value)
    return nil if value.blank?
    month = Integer(value.to_s, exception: false)
    return nil unless month
    return nil unless month.between?(1, 12)
    month
  end
end
