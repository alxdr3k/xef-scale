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
    if @membership.role == "owner"
      redirect_to settings_workspace_path(@workspace), alert: I18n.t("workspace_memberships.flash.owner_role_immutable")
      return
    end

    if @membership.update(membership_params)
      redirect_to settings_workspace_path(@workspace), notice: I18n.t("workspace_memberships.flash.role_updated")
    else
      redirect_to settings_workspace_path(@workspace), alert: I18n.t("workspace_memberships.flash.role_update_failed")
    end
  end

  def destroy
    @membership = @workspace.workspace_memberships.find(params[:id])

    # Cannot remove owner
    if @membership.role == "owner"
      redirect_to settings_workspace_path(@workspace), alert: I18n.t("workspace_memberships.flash.owner_remove_blocked")
      return
    end

    # Cannot remove yourself
    if @membership.user == current_user
      redirect_to settings_workspace_path(@workspace), alert: I18n.t("workspace_memberships.flash.self_remove_blocked")
      return
    end

    @membership.destroy
    redirect_to settings_workspace_path(@workspace), notice: I18n.t("workspace_memberships.flash.removed")
  end

  private

  def membership_params
    params.require(:workspace_membership).permit(:role)
  end
end
