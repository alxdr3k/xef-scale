class ImportRepairNotifier
  def self.call(parsing_session)
    new(parsing_session).call
  end

  def initialize(parsing_session)
    @parsing_session = parsing_session
    @workspace = parsing_session.workspace
  end

  def call
    return unless @parsing_session.open_import_issues.exists?

    recipients.each do |user|
      Notification.create_import_repair_needed!(@parsing_session, user)
    rescue StandardError => e
      Rails.logger.error "[ImportRepairNotifier] Failed to notify user #{user.id}: #{e.class} #{e.message}"
    end
  end

  private

  def recipients
    @workspace.notification_recipients(roles: %w[co_owner member_write])
  end
end
