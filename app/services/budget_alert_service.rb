class BudgetAlertService
  def self.create_for_transactions!(workspace, transactions)
    new(workspace).create_for_dates!(transactions.map(&:date))
  end

  def initialize(workspace)
    @workspace = workspace
  end

  def create_for_dates!(dates)
    return unless @workspace.budget

    dates.compact.map { |date| [ date.year, date.month ] }.uniq.each do |year, month|
      create_for_month!(year, month)
    end
  end

  private

  def create_for_month!(year, month)
    progress = @workspace.budget.progress_for_month(year, month)
    alert_type = alert_type_for(progress)
    return unless alert_type

    @workspace.members.find_each do |member|
      next if already_alerted?(member, alert_type, year, month)

      Notification.create_budget_alert!(@workspace, member, alert_type, progress, year: year, month: month)
    end
  end

  def alert_type_for(progress)
    if progress[:percentage] >= 100
      "budget_exceeded"
    elsif progress[:percentage] >= 80
      "budget_warning"
    end
  end

  def already_alerted?(member, alert_type, year, month)
    Notification.where(
      workspace: @workspace,
      user: member,
      notification_type: alert_type,
      target_year: year,
      target_month: month
    ).exists?
  end
end
