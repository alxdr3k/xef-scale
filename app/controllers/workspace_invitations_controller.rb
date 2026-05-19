class WorkspaceInvitationsController < ApplicationController
  before_action :authenticate_user!, except: [ :join ]
  before_action :set_workspace, only: [ :index, :create, :destroy ]
  before_action :require_workspace_admin_access, only: [ :index, :create, :destroy ]

  def index
    @invitations = @workspace.workspace_invitations.includes(:invited_by)
  end

  def create
    @invitation = @workspace.workspace_invitations.build(invitation_params)
    @invitation.invited_by = current_user

    if @invitation.save
      redirect_to settings_workspace_path(@workspace),
                  notice: I18n.t("workspace_invitations.flash.created", url: join_workspace_url(@invitation.token))
    else
      redirect_to settings_workspace_path(@workspace), alert: I18n.t("workspace_invitations.flash.create_failed")
    end
  end

  def destroy
    @invitation = @workspace.workspace_invitations.find(params[:id])
    @invitation.destroy
    redirect_to settings_workspace_path(@workspace), notice: I18n.t("workspace_invitations.flash.destroyed")
  end

  def join
    @invitation = WorkspaceInvitation.find_by(token: params[:token])

    if @invitation.nil?
      redirect_to root_path, alert: I18n.t("workspace_invitations.flash.invalid_token")
      return
    end

    unless @invitation.usable?
      redirect_to root_path, alert: I18n.t("workspace_invitations.flash.expired_token")
      return
    end

    if user_signed_in?
      process_join
    else
      session[:invitation_token] = params[:token]
      redirect_to new_user_session_path, notice: I18n.t("workspace_invitations.flash.sign_in_required")
    end
  end

  private

  def invitation_params
    params.require(:workspace_invitation).permit(:expires_at, :max_uses)
  end

  def process_join
    workspace = @invitation.workspace

    if current_user.workspaces.include?(workspace)
      redirect_to workspace_path(workspace), notice: I18n.t("workspace_invitations.flash.already_member")
      return
    end

    if @invitation.use!
      workspace.workspace_memberships.create!(user: current_user, role: "member_read")
      redirect_to workspace_path(workspace), notice: I18n.t("workspace_invitations.flash.joined")
    else
      redirect_to root_path, alert: I18n.t("workspace_invitations.flash.join_failed")
    end
  end
end
