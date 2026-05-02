class ImportIssuesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :require_workspace_access
  before_action :require_workspace_write_access
  before_action :set_import_issue

  def update
    service = ImportIssueResolutionService.new(@import_issue, user: current_user)
    action = params[:resolution_action].to_s
    result = case action
    when "dismiss"
      service.dismiss!
    when "create_new"
      service.promote_as_new!
    when "", "update_fields"
      service.update_missing_fields!(import_issue_params)
    else
      Rails.logger.warn "[ImportIssues#update] Unknown resolution_action: #{action.inspect}"
      return redirect_to repair_return_path, alert: "알 수 없는 처리 방식입니다."
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
