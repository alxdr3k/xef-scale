class TestSessionsController < ApplicationController
  before_action :ensure_test_environment
  skip_forgery_protection only: :ai_consent

  def create
    user = if params[:email].present?
             User.find_by!(email: params[:email])
    else
             User.find(params[:user_id])
    end
    sign_in(user)
    redirect_to root_path
  end

  def ai_consent
    return head :unauthorized unless current_user

    workspace = if params[:workspace_id].present?
                  current_user.workspaces.find(params[:workspace_id])
    elsif params[:workspace_name].present?
                  current_user.workspaces.find_by!(name: params[:workspace_name])
    else
                  current_user.workspaces.first!
    end

    acknowledged = ActiveModel::Type::Boolean.new.cast(params[:acknowledged])
    workspace.update!(ai_consent_acknowledged_at: acknowledged ? Time.current : nil)
    head :no_content
  end

  private

  def ensure_test_environment
    head :forbidden unless Rails.env.test? || Rails.env.development?
  end
end
