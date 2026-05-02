class ImportIssuesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :require_workspace_access
  before_action :require_workspace_write_access
  before_action :set_import_issue

  def update
    service = ImportIssueResolutionService.new(@import_issue, user: current_user)
    result = case params[:resolution_action].to_s
    when "dismiss"
      service.dismiss!
    when "create_new"
      service.promote_as_new!
    else
      service.update_missing_fields!(import_issue_params)
    end

    if result.success?
      redirect_to repair_return_path, notice: result.message
    else
      redirect_to repair_return_path, alert: result.message
    end
  end

  private

  def set_import_issue
    @import_issue = @workspace.import_issues.find(params[:id])
  end

  def import_issue_params
    params.fetch(:import_issue, {}).permit(:date, :merchant, :amount)
  end

  def repair_return_path
    workspace_transactions_path(
      @workspace,
      repair: "required",
      import_session_id: @import_issue.parsing_session_id
    )
  end
end
