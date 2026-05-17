# frozen_string_literal: true

class DatabaseBackupService
  BACKUP_DIR = Rails.root.join("storage", "backups").freeze
  ALLOWED_ENVIRONMENTS = %w[development test].freeze

  class UnsupportedEnvironmentError < StandardError; end

  def initialize(database_path: default_database_path, backup_dir: BACKUP_DIR, environment: Rails.env)
    @database_path = Pathname.new(database_path.to_s)
    @backup_dir = Pathname.new(backup_dir.to_s)
    @environment = environment.to_s

    validate_environment!
    FileUtils.mkdir_p(@backup_dir)
  end

  def backup(label = nil)
    timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
    backup_filename = "#{@environment}_import_backup_#{timestamp}#{label_suffix(label)}.sqlite3"
    backup_path = @backup_dir.join(backup_filename)

    unless File.exist?(@database_path)
      raise "Database file not found: #{@database_path}"
    end

    FileUtils.cp(@database_path, backup_path)
    Rails.logger.info "Database backed up to: #{backup_path}"

    backup_path.to_s
  end

  def list_backups
    Dir.glob(@backup_dir.join("*.sqlite3")).sort
  end

  def restore(backup_path)
    unless File.exist?(backup_path)
      raise "Backup file not found: #{backup_path}"
    end

    FileUtils.cp(backup_path, @database_path)
    Rails.logger.info "Database restored from: #{backup_path}"
  end

  private

  def default_database_path
    database = ActiveRecord::Base.connection_db_config.database
    path = Pathname.new(database.to_s)
    path.absolute? ? path : Rails.root.join(path)
  end

  def validate_environment!
    return if ALLOWED_ENVIRONMENTS.include?(@environment)

    raise UnsupportedEnvironmentError,
          "DatabaseBackupService is development/import-only and cannot run in #{@environment}"
  end

  def label_suffix(label)
    return "" if label.blank?

    sanitized = label.to_s.gsub(/[^a-zA-Z0-9_-]+/, "_").gsub(/\A_+|_+\z/, "")
    sanitized.present? ? "_#{sanitized}" : ""
  end
end
