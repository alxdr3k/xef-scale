class ApplicationController < ActionController::Base
  include Pundit::Authorization
  include Pagy::Backend

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  before_action :configure_permitted_parameters, if: :devise_controller?

  helper_method :current_workspace

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized
  rescue_from Pagy::OverflowError, with: :handle_pagy_overflow

  protected

  def after_sign_in_path_for(resource)
    token = session.delete(:invitation_token)
    if token.present?
      join_workspace_path(token: token)
    else
      super
    end
  end

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [ :name ])
    devise_parameter_sanitizer.permit(:account_update, keys: [ :name, :avatar_url ])
  end

  def current_workspace
    return @current_workspace if defined?(@current_workspace)

    @current_workspace = if params[:workspace_id]
                           current_user&.workspaces&.find_by(id: params[:workspace_id])
    elsif session[:workspace_id]
                           current_user&.workspaces&.find_by(id: session[:workspace_id])
    else
                           current_user&.workspaces&.first
    end
  end

  def set_workspace
    @workspace = current_user.workspaces.find(params[:workspace_id] || params[:id])
    session[:workspace_id] = @workspace.id
  rescue ActiveRecord::RecordNotFound
    redirect_to workspaces_path, alert: "워크스페이스를 찾을 수 없습니다."
  end

  def require_workspace_access
    unless current_user.can_read?(@workspace)
      redirect_to workspaces_path, alert: "이 워크스페이스에 접근할 권한이 없습니다."
    end
  end

  def require_workspace_write_access
    unless current_user.can_write?(@workspace)
      redirect_to workspace_path(@workspace), alert: "이 워크스페이스를 수정할 권한이 없습니다."
    end
  end

  def require_workspace_admin_access
    unless current_user.admin_of?(@workspace)
      redirect_to workspace_path(@workspace), alert: "관리자 권한이 필요합니다."
    end
  end

  private

  def user_not_authorized
    flash[:alert] = "이 작업을 수행할 권한이 없습니다."
    redirect_back(fallback_location: root_path)
  end

  def handle_pagy_overflow(exception)
    render plain: "존재하지 않는 페이지입니다.", status: :not_found
  end
end
