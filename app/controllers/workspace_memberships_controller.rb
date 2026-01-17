class WorkspaceMembershipsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :require_workspace_admin_access

  def index
    @memberships = @workspace.workspace_memberships.includes(:user)
  end

  def update
    @membership = @workspace.workspace_memberships.find(params[:id])

    # Cannot change owner role
    if @membership.role == 'owner'
      redirect_to settings_workspace_path(@workspace), alert: '소유자의 역할은 변경할 수 없습니다.'
      return
    end

    if @membership.update(membership_params)
      redirect_to settings_workspace_path(@workspace), notice: '멤버 역할이 변경되었습니다.'
    else
      redirect_to settings_workspace_path(@workspace), alert: '역할 변경에 실패했습니다.'
    end
  end

  def destroy
    @membership = @workspace.workspace_memberships.find(params[:id])

    # Cannot remove owner
    if @membership.role == 'owner'
      redirect_to settings_workspace_path(@workspace), alert: '소유자는 제거할 수 없습니다.'
      return
    end

    # Cannot remove yourself
    if @membership.user == current_user
      redirect_to settings_workspace_path(@workspace), alert: '자기 자신은 제거할 수 없습니다.'
      return
    end

    @membership.destroy
    redirect_to settings_workspace_path(@workspace), notice: '멤버가 제거되었습니다.'
  end

  private

  def membership_params
    params.require(:workspace_membership).permit(:role)
  end
end
