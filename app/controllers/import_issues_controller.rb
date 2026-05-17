class ImportIssuesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :require_workspace_access
  before_action :require_workspace_write_access
  before_action :set_import_issue

  def update
    service = ImportIssueResolutionService.new(@import_issue, user: current_user)
    result =
      if params[:resolution_action].to_s == "dismiss"
        service.dismiss!
      else
        service.update_missing_fields!(import_issue_params)
      end

    redirect_path = review_workspace_parsing_session_path(@workspace, @import_issue.parsing_session)
    if result.success?
      redirect_to redirect_path, notice: result.message
    else
      redirect_to redirect_path, alert: result.message
    end
  end

  private

  def set_workspace
    @workspace = current_user.workspaces.find(params[:workspace_id])
  end

  def require_workspace_access
    redirect_to root_path, alert: "접근 권한이 없습니다." unless current_user.can_read?(@workspace)
  end

  def require_workspace_write_access
    redirect_to root_path, alert: "수정 권한이 없습니다." unless current_user.can_write?(@workspace)
  end

  def set_import_issue
    @import_issue = @workspace.import_issues.find(params[:id])
  end

  def import_issue_params
    params.fetch(:import_issue, {}).permit(:date, :merchant, :amount)
  end
end
