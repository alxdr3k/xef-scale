class CategoriesController < ApplicationController
  include ActionView::RecordIdentifier

  before_action :authenticate_user!
  before_action :set_workspace
  before_action :require_workspace_admin_access
  before_action :set_category, only: [ :edit, :update, :destroy ]

  # Phase 3.4 (ADR-0004 / ui-redesign-plan §3.4): 카테고리와 학습된 매핑을 같은
  # 페이지에 *두 섹션*으로 결합한다. 매핑은 최근 N개 미리보기 + 전체 보기 CTA로
  # workspace_category_mappings_path를 노출. CategoryMappingsController는 그대로 유지.
  RECENT_MAPPINGS_LIMIT = 10

  def index
    @categories = @workspace.categories.order(:name)
    @recent_mappings = @workspace.category_mappings
                                 .includes(:category)
                                 .order(updated_at: :desc)
                                 .limit(RECENT_MAPPINGS_LIMIT)
    @total_mappings_count = @workspace.category_mappings.count
  end

  def new
    @category = @workspace.categories.build
    @slideover = params[:slideover] == "true"
    @transaction_id = params[:transaction_id]

    if @slideover
      render partial: "slideover_form", layout: false
    end
  end

  def create
    @category = @workspace.categories.build(category_params)
    @slideover = params[:slideover] == "true"
    @transaction_id = params[:transaction_id]
    # Codex hotfix A: 슬라이드오버가 review 화면에서 열렸으면 parsing_session_id가
    # query string으로 따라온다. row re-render가 review context를 잃으면 이후
    # 인라인 편집/카테고리 변경이 session-scoped guard(reject_if_finalized)를
    # 우회하므로 반드시 보존해야 한다. workspace 소속/세션 소속을 검증한 뒤
    # @parsing_session을 설정 → partial이 explicit URL을 emit한다.
    if @slideover && params[:parsing_session_id].present?
      @parsing_session = @workspace.parsing_sessions.find_by(id: params[:parsing_session_id])
    end

    if @category.save
      if @slideover && @transaction_id.present?
        # Assign category to transaction and return turbo stream.
        # ADR-0011 §Decision 3: 슬라이드오버 "+ 새 카테고리 만들기"는 사용자가
        # 명시적으로 새 카테고리를 만들고 거래에 적용한 흐름이므로 manual_set.
        # review context면 transaction이 그 session에 속하는지 확인 — cross-session
        # row 변조를 막는다.
        scope = @parsing_session ? @parsing_session.transactions : @workspace.transactions
        @transaction = scope.find(@transaction_id)
        @transaction.update(category_id: @category.id, classification_source: "manual_set")
        @categories = @workspace.categories.order(:name)
        flash.now[:notice] = "카테고리가 추가되고 거래에 적용되었습니다."
        broadcast_html = helpers.content_tag(:div, "",
          data: {
            controller: "category-broadcast",
            category_broadcast_id_value: @category.id,
            category_broadcast_name_value: @category.name,
            category_broadcast_color_value: @category.color
          })
        row_locals = { transaction: @transaction }
        if @parsing_session
          # Re-render with review-context locals so inline edit URL / category
          # selector URL remain session-scoped on the replaced row.
          row_locals.merge!(
            read_only: false,
            reviewable: true,
            categories: @categories
          )
        end
        render turbo_stream: [
          turbo_stream.replace(dom_id(@transaction), partial: "transactions/transaction_row", locals: row_locals),
          turbo_stream.update("flash", partial: "shared/flash"),
          turbo_stream.append("slideover-content", broadcast_html + '<div data-controller="slideover-close"></div>'.html_safe)
        ]
      else
        respond_to do |format|
          format.html { redirect_to workspace_categories_path(@workspace), notice: "카테고리가 추가되었습니다." }
          format.turbo_stream { flash.now[:notice] = "카테고리가 추가되었습니다." }
        end
      end
    else
      if @slideover
        render partial: "slideover_form", layout: false, status: :unprocessable_entity
      else
        render :new, status: :unprocessable_entity
      end
    end
  end

  def edit
  end

  def update
    if @category.update(category_params)
      respond_to do |format|
        format.html { redirect_to workspace_categories_path(@workspace), notice: "카테고리가 수정되었습니다." }
        format.turbo_stream { flash.now[:notice] = "카테고리가 수정되었습니다." }
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @category.destroy

    respond_to do |format|
      format.html { redirect_to workspace_categories_path(@workspace), notice: "카테고리가 삭제되었습니다." }
      format.turbo_stream { flash.now[:notice] = "카테고리가 삭제되었습니다." }
    end
  end

  private

  def set_category
    @category = @workspace.categories.find(params[:id])
  end

  def category_params
    params.require(:category).permit(:name, :keyword, :color)
  end
end
