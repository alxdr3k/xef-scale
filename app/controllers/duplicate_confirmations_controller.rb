class DuplicateConfirmationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :require_workspace_write_access

  def update
    @parsing_session = @workspace.parsing_sessions.find(params[:parsing_session_id])
    @duplicate_confirmation = @parsing_session.duplicate_confirmations.find(params[:id])

    @duplicate_confirmation.resolve!(params[:decision])

    respond_to do |format|
      format.html do
        redirect_to workspace_parsing_session_path(@workspace, @parsing_session),
                    notice: "중복 처리가 완료되었습니다."
      end
      format.turbo_stream { flash.now[:notice] = "중복 처리가 완료되었습니다." }
    end
  rescue ArgumentError => e
    redirect_to workspace_parsing_session_path(@workspace, @parsing_session),
                alert: e.message
  end
end
