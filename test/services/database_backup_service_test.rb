require "test_helper"
require "tmpdir"

class DatabaseBackupServiceTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  test "backup copies configured database into configured backup directory" do
    Dir.mktmpdir do |dir|
      database_path = File.join(dir, "development.sqlite3")
      backup_dir = File.join(dir, "backups")
      File.write(database_path, "sqlite-content")

      travel_to Time.zone.local(2026, 4, 30, 12, 34, 56) do
        path = DatabaseBackupService.new(
          database_path: database_path,
          backup_dir: backup_dir,
          environment: "development"
        ).backup("pre import")

        assert_equal File.join(backup_dir, "development_import_backup_20260430_123456_pre_import.sqlite3"), path
        assert_equal "sqlite-content", File.read(path)
      end
    end
  end

  test "list_backups returns sorted sqlite backup files from configured backup directory" do
    Dir.mktmpdir do |dir|
      backup_dir = File.join(dir, "backups")
      database_path = File.join(dir, "development.sqlite3")
      FileUtils.mkdir_p(backup_dir)
      File.write(database_path, "sqlite-content")
      second = File.join(backup_dir, "development_import_backup_20260430_120001.sqlite3")
      first = File.join(backup_dir, "development_import_backup_20260430_120000.sqlite3")
      ignored = File.join(backup_dir, "notes.txt")
      File.write(second, "second")
      File.write(first, "first")
      File.write(ignored, "ignored")

      backups = DatabaseBackupService.new(
        database_path: database_path,
        backup_dir: backup_dir,
        environment: "development"
      ).list_backups

      assert_equal [ first, second ], backups
    end
  end

  test "restore copies selected backup over configured database path" do
    Dir.mktmpdir do |dir|
      database_path = File.join(dir, "development.sqlite3")
      backup_dir = File.join(dir, "backups")
      backup_path = File.join(dir, "backup.sqlite3")
      File.write(database_path, "old")
      File.write(backup_path, "restored")

      DatabaseBackupService.new(
        database_path: database_path,
        backup_dir: backup_dir,
        environment: "development"
      ).restore(backup_path)

      assert_equal "restored", File.read(database_path)
    end
  end

  test "unsupported environments are rejected" do
    error = assert_raises(DatabaseBackupService::UnsupportedEnvironmentError) do
      DatabaseBackupService.new(
        database_path: "/tmp/production.sqlite3",
        backup_dir: "/tmp/backups",
        environment: "production"
      )
    end

    assert_includes error.message, "development/import-only"
  end

  test "backup raises when configured database file does not exist" do
    Dir.mktmpdir do |dir|
      missing_database_path = File.join(dir, "missing.sqlite3")

      error = assert_raises(RuntimeError) do
        DatabaseBackupService.new(
          database_path: missing_database_path,
          backup_dir: File.join(dir, "backups"),
          environment: "development"
        ).backup
      end

      assert_includes error.message, "Database file not found"
    end
  end
end
