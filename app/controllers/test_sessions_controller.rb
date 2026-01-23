class TestSessionsController < ApplicationController
  before_action :ensure_test_environment

  def create
    user = if params[:email].present?
             User.find_by!(email: params[:email])
    else
             User.find(params[:user_id])
    end
    sign_in(user)
    redirect_to root_path
  end

  private

  def ensure_test_environment
    head :forbidden unless Rails.env.test? || Rails.env.development?
  end
end
