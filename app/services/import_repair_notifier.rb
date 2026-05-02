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
    end
  end

  private

  def recipients
    users = []
    users << @workspace.owner if @workspace.owner

    @workspace.workspace_memberships.where(role: %w[co_owner member_write]).find_each do |membership|
      next if membership.user_id == @workspace.owner_id

      users << membership.user
    end

    users.compact
  end
end
