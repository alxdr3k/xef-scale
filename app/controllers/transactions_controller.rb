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
        format.html { redirect_to workspace_transactions_path(@workspace), notice: I18n.t("transactions.flash.created") }
        format.turbo_stream { flash[:notice] = I18n.t("transactions.flash.created") }
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
    old_merchant = @transaction.merchant
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
      category_changed = category_id_submitted && @transaction.category_id != old_category_id
      if category_changed
        new_source = @transaction.category_id.present? ? "manual_set" : nil
        @transaction.update_column(:classification_source, new_source)
      end

      # ADR-0011 §Decision 3 (Phase 5 cleanup): merchant가 바뀌면 새 merchant
      # 기준으로 provenance 재평가. inline_update / ReviewsController#update_transaction
      # form path와 동일 의미를 ledger full edit route에도 적용한다.
      # 사용자가 같은 요청에서 category까지 명시 변경했다면 user intent가 우선이므로
      # rematch로 덮지 않는다.
      merchant_changed = old_merchant != @transaction.merchant
      apply_merchant_rematch_policy!(@transaction) if merchant_changed && !category_changed

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
        format.html { redirect_to params[:return_to].presence || workspace_transactions_path(@workspace), notice: I18n.t("transactions.flash.updated") }
        format.turbo_stream { flash[:notice] = I18n.t("transactions.flash.updated") }
      end
    else
      @categories = @workspace.categories
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @transaction.soft_delete!

    respond_to do |format|
      format.html { redirect_to workspace_transactions_path(@workspace), notice: I18n.t("transactions.flash.destroyed") }
      format.turbo_stream { flash.now[:notice] = I18n.t("transactions.flash.destroyed") }
    end
  end

  def toggle_allowance
    if @transaction.allowance?
      AllowanceTransaction.unmark_as_allowance!(@transaction, current_user)
      notice = I18n.t("transactions.flash.allowance_unset")
    else
      AllowanceTransaction.mark_as_allowance!(@transaction, current_user)
      notice = I18n.t("transactions.flash.allowance_set")
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
          render json: { success: false, errors: [ I18n.t("transactions.flash.wrong_workspace_category") ] },
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
      redirect_to workspace_transactions_path(@workspace), alert: I18n.t("transactions.flash.empty_selection")
      return
    end

    action = params[:bulk_action]
    transactions = @workspace.transactions.active.where(id: transaction_ids)

    case action
    when "delete"
      count = transactions.count
      transactions.find_each(&:soft_delete!)
      notice = I18n.t("transactions.flash.bulk_deleted", count: count)
    when "mark_allowance"
      count = 0
      transactions.find_each do |tx|
        unless tx.allowance?
          AllowanceTransaction.mark_as_allowance!(tx, current_user)
          count += 1
        end
      end
      notice = I18n.t("transactions.flash.bulk_allowance_set", count: count)
    when "unmark_allowance"
      count = 0
      transactions.find_each do |tx|
        if tx.allowance?
          AllowanceTransaction.unmark_as_allowance!(tx, current_user)
          count += 1
        end
      end
      notice = I18n.t("transactions.flash.bulk_allowance_unset", count: count)
    when "change_category"
      # Codex hotfix B: invalid/blank category_id를 nil clear로 silent 해석하지
      # 않는다 — bulk action은 파괴 범위가 크므로 422/alert로 막는다. 단건
      # quick_update_category와 contract를 맞춤.
      if params[:category_id].blank?
        redirect_to workspace_transactions_path(@workspace),
                    alert: I18n.t("transactions.flash.category_required")
        return
      end
      category = @workspace.categories.find_by(id: params[:category_id])
      unless category
        redirect_to workspace_transactions_path(@workspace),
                    alert: I18n.t("transactions.flash.invalid_category")
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
      notice = I18n.t("transactions.flash.bulk_category_changed", count: count)
    else
      notice = I18n.t("transactions.flash.unknown_action")
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
      :date, :merchant, :description, :amount, :notes,
      :category_id, :payment_type,
      :installment_month, :installment_total
    )
  end

  def generate_csv(transactions)
    require "csv"
    CSV.generate(headers: true, encoding: "UTF-8") do |csv|
      csv << [
        I18n.t("transactions.csv.header_date"),
        I18n.t("transactions.csv.header_merchant"),
        I18n.t("transactions.csv.header_amount"),
        I18n.t("transactions.csv.header_category"),
        I18n.t("transactions.csv.header_notes")
      ]
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
  # provenance를 재평가. 정책은 MerchantRematchPolicy 서비스로 추출되어
  # ReviewsController와 공유한다 — review/ledger 양쪽 경로가 같은 의미를 가져야 함.
  def apply_merchant_rematch_policy!(transaction)
    MerchantRematchPolicy.apply!(@workspace, transaction)
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
