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
                  notice: "초대 링크가 생성되었습니다: #{join_workspace_url(@invitation.token)}"
    else
      redirect_to settings_workspace_path(@workspace), alert: "초대 링크 생성에 실패했습니다."
    end
  end

  def destroy
    @invitation = @workspace.workspace_invitations.find(params[:id])
    @invitation.destroy
    redirect_to settings_workspace_path(@workspace), notice: "초대 링크가 삭제되었습니다."
  end

  def join
    @invitation = WorkspaceInvitation.find_by(token: params[:token])

    if @invitation.nil?
      redirect_to root_path, alert: "유효하지 않은 초대 링크입니다."
      return
    end

    unless @invitation.usable?
      redirect_to root_path, alert: "만료되었거나 사용할 수 없는 초대 링크입니다."
      return
    end

    if user_signed_in?
      process_join
    else
      session[:invitation_token] = params[:token]
      redirect_to new_user_session_path, notice: "먼저 로그인해 주세요."
    end
  end

  private

  def invitation_params
    params.require(:workspace_invitation).permit(:expires_at, :max_uses)
  end

  def process_join
    workspace = @invitation.workspace

    if current_user.workspaces.include?(workspace)
      redirect_to workspace_path(workspace), notice: "이미 이 워크스페이스의 멤버입니다."
      return
    end

    if @invitation.use!
      workspace.workspace_memberships.create!(user: current_user, role: "member_read")
      redirect_to workspace_path(workspace), notice: "워크스페이스에 참여했습니다!"
    else
      redirect_to root_path, alert: "워크스페이스 참여에 실패했습니다."
    end
  end
end
