class WorkspacesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace, only: [ :show, :edit, :update, :destroy, :settings ]
  before_action :require_workspace_access, only: [ :show ]
  before_action :require_workspace_admin_access, only: [ :edit, :update, :destroy, :settings ]

  def index
    @workspaces = current_user.workspaces.includes(:owner)
  end

  def show
    @year = params[:year]&.to_i || Date.current.year
    @month = params[:month]&.to_i || Date.current.month

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
      redirect_to @workspace, notice: "워크스페이스가 생성되었습니다."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
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
    @memberships = @workspace.workspace_memberships.includes(:user)
    @invitations = @workspace.workspace_invitations.available.includes(:invited_by)
  end

  private

  def workspace_params
    params.require(:workspace).permit(:name)
  end
end
