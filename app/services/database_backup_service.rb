# frozen_string_literal: true

class DatabaseBackupService
  BACKUP_DIR = Rails.root.join("storage", "backups").freeze

  def initialize
    FileUtils.mkdir_p(BACKUP_DIR)
  end

  def backup(label = nil)
    timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
    suffix = label ? "_#{label}" : ""
    backup_filename = "development_backup_#{timestamp}#{suffix}.sqlite3"
    backup_path = BACKUP_DIR.join(backup_filename)

    source_db = Rails.root.join("storage", "development.sqlite3")

    unless File.exist?(source_db)
      raise "Database file not found: #{source_db}"
    end

    FileUtils.cp(source_db, backup_path)
    Rails.logger.info "Database backed up to: #{backup_path}"

    backup_path.to_s
  end

  def list_backups
    Dir.glob(BACKUP_DIR.join("*.sqlite3")).sort
  end

  def restore(backup_path)
    unless File.exist?(backup_path)
      raise "Backup file not found: #{backup_path}"
    end

    source_db = Rails.root.join("storage", "development.sqlite3")
    FileUtils.cp(backup_path, source_db)
    Rails.logger.info "Database restored from: #{backup_path}"
  end
end
