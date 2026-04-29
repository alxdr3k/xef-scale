class WorkspacesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace, only: [ :show, :edit, :update, :destroy, :settings ]
  before_action :require_workspace_access, only: [ :show ]
  before_action :require_workspace_admin_access, only: [ :edit, :update, :destroy, :settings ]

  def index
    @workspaces = current_user.workspaces.includes(:owner)
  end

  def show
    @year = sanitize_year(params[:year]) || Date.current.year
    @month = sanitize_month(params[:month]) || Date.current.month

    @transactions = @workspace.transactions
                              .active
                              .for_month(@year, @month)
                              .includes(:category, :financial_institution)
                              .order(date: :desc)
  end

  def new
    @workspace = Workspace.new
  end

  def create
    @workspace = current_user.owned_workspaces.build(workspace_params)

    if @workspace.save
      redirect_to dashboard_path, notice: "워크스페이스가 생성되었습니다."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if budget_settings_update?
      update_budget_settings
      return
    end

    if @workspace.update(workspace_params)
      redirect_to @workspace, notice: "워크스페이스가 업데이트되었습니다."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @workspace.destroy
    redirect_to workspaces_path, notice: "워크스페이스가 삭제되었습니다."
  end

  def settings
    load_settings_context
  end

  private

  def budget_settings_update?
    params[:settings_context] == "budget"
  end

  def update_budget_settings
    @budget = @workspace.budget || @workspace.build_budget
    amount = params.dig(:budget, :monthly_amount).to_s.delete(",").strip

    if amount.blank?
      @budget.destroy! if @budget.persisted?
      redirect_to settings_workspace_path(@workspace), notice: "월 예산이 해제되었습니다."
    elsif @budget.update(monthly_amount: amount)
      redirect_to settings_workspace_path(@workspace), notice: "월 예산이 저장되었습니다."
    else
      load_settings_context
      render :settings, status: :unprocessable_entity
    end
  end

  def load_settings_context
    @memberships = @workspace.workspace_memberships.includes(:user)
    @invitations = @workspace.workspace_invitations.available.includes(:invited_by)
    @budget ||= @workspace.budget || @workspace.build_budget
  end

  def workspace_params
    attrs = params.require(:workspace).permit(
      :name,
      :ai_text_parsing_enabled,
      :ai_image_parsing_enabled,
      :ai_category_suggestions_enabled
    )

    consent = params.dig(:workspace, :ai_consent_acknowledged)
    if ActiveModel::Type::Boolean.new.cast(consent) && @workspace&.ai_consent_acknowledged_at.nil?
      attrs[:ai_consent_acknowledged_at] = Time.current
    end

    attrs
  end
end
