class AddTargetPeriodToNotifications < ActiveRecord::Migration[8.1]
  def change
    add_column :notifications, :target_year, :integer
    add_column :notifications, :target_month, :integer
    add_index :notifications, [ :workspace_id, :user_id, :notification_type, :target_year, :target_month ],
              name: "index_notifications_on_budget_dedup"
  end
end
