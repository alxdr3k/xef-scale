class NotificationsController < ApplicationController
  before_action :authenticate_user!

  def index
    @notifications = current_user.notifications
                                 .recent
                                 .includes(:workspace, :notifiable)
    @pagy, @notifications = pagy(@notifications, items: 20)

    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  def mark_read
    @notification = current_user.notifications.find(params[:id])
    @notification.mark_as_read!

    respond_to do |format|
      format.html { redirect_back(fallback_location: notifications_path) }
      format.turbo_stream
      format.json { render json: { success: true } }
    end
  end

  def mark_all_read
    workspace = params[:workspace_id] ? current_user.workspaces.find(params[:workspace_id]) : nil
    Notification.mark_all_read!(current_user, workspace)

    respond_to do |format|
      format.html { redirect_back(fallback_location: notifications_path) }
      format.turbo_stream
      format.json { render json: { success: true } }
    end
  end

  def unread_count
    workspace = params[:workspace_id] ? current_user.workspaces.find_by(id: params[:workspace_id]) : nil
    count = current_user.unread_notifications_count(workspace)
    render json: { count: count }
  end
end
