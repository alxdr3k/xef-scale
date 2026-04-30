require "test_helper"
require "tmpdir"
require "sqlite3"

class SqliteBackupServiceTest < ActiveSupport::TestCase
  FIXED_TIME = Time.zone.local(2026, 4, 30, 12, 34, 56)

  test "backup uses sqlite backup api and verifies integrity" do
    with_tmpdir do |dir|
      database_path = dir.join("source.sqlite3")
      backup_dir = dir.join("backups")
      create_database(database_path, [ "coffee", "rent" ])

      result = SqliteBackupService.new(
        environment: "test",
        role: :primary,
        database_path: database_path,
        backup_dir: backup_dir,
        clock: -> { FIXED_TIME }
      ).backup(label: "pre import")

      expected_path = backup_dir.join("test_primary_sqlite_backup_20260430_123456_pre_import.sqlite3")
      assert_equal expected_path.to_s, result.backup_path
      assert_equal "ok", result.integrity_check
      assert_operator result.bytes, :>, 0
      assert_equal [ "coffee", "rent" ], read_entries(expected_path)
    end
  end

  test "backup handles multi step sqlite copy" do
    with_tmpdir do |dir|
      database_path = dir.join("large.sqlite3")
      backup_dir = dir.join("backups")
      create_large_database(database_path, rows: 250)

      result = SqliteBackupService.new(
        environment: "test",
        role: :primary,
        database_path: database_path,
        backup_dir: backup_dir,
        clock: -> { FIXED_TIME }
      ).backup

      assert_equal "ok", result.integrity_check
      assert_equal 250, large_entry_count(result.backup_path)
    end
  end

  test "backup aborts when max step budget is exceeded" do
    with_tmpdir do |dir|
      database_path = dir.join("large.sqlite3")
      backup_dir = dir.join("backups")
      create_large_database(database_path, rows: 250)

      assert_raises(SqliteBackupService::BackupError) do
        SqliteBackupService.new(
          environment: "test",
          role: :primary,
          database_path: database_path,
          backup_dir: backup_dir,
          clock: -> { FIXED_TIME },
          backup_max_steps: 1
        ).backup
      end

      assert_empty Dir.glob(backup_dir.join("*.sqlite3"))
    end
  end

  test "restore verifies backup before copying over target database" do
    with_tmpdir do |dir|
      database_path = dir.join("target.sqlite3")
      backup_path = dir.join("backup.sqlite3")
      create_database(database_path, [ "old" ])
      create_database(backup_path, [ "new", "rows" ])

      result = SqliteBackupService.new(
        environment: "test",
        role: :primary,
        database_path: database_path,
        backup_dir: dir.join("backups"),
        clock: -> { FIXED_TIME }
      ).restore(backup_path, quiesced: true)

      assert_equal database_path.to_s, result.database_path
      assert_equal backup_path.to_s, result.backup_path
      assert_equal "ok", result.integrity_check
      assert_equal [ "new", "rows" ], read_entries(database_path)
    end
  end

  test "restore requires explicit quiescence before copying backup" do
    with_tmpdir do |dir|
      database_path = dir.join("target.sqlite3")
      backup_path = dir.join("backup.sqlite3")
      create_database(database_path, [ "old" ])
      create_database(backup_path, [ "new" ])

      assert_raises(SqliteBackupService::RestoreRequiresQuiescenceError) do
        SqliteBackupService.new(
          environment: "test",
          role: :primary,
          database_path: database_path,
          backup_dir: dir.join("backups"),
          clock: -> { FIXED_TIME }
        ).restore(backup_path)
      end

      assert_equal [ "old" ], read_entries(database_path)
    end
  end

  test "restore rejects corrupt backup without changing target database" do
    with_tmpdir do |dir|
      database_path = dir.join("target.sqlite3")
      backup_path = dir.join("broken.sqlite3")
      create_database(database_path, [ "old" ])
      File.write(backup_path, "not sqlite")

      assert_raises(SqliteBackupService::IntegrityError) do
        SqliteBackupService.new(
          environment: "test",
          role: :primary,
          database_path: database_path,
          backup_dir: dir.join("backups"),
          clock: -> { FIXED_TIME },
          busy_timeout_ms: 50
        ).restore(backup_path, quiesced: true)
      end

      assert_equal [ "old" ], read_entries(database_path)
    end
  end

  test "backup continues when source checkpoint is busy" do
    with_tmpdir do |dir|
      database_path = dir.join("source.sqlite3")
      backup_dir = dir.join("backups")
      create_database(database_path, [ "old" ])

      reader = SQLite3::Database.new(database_path.to_s, readonly: true)
      reader.execute("BEGIN")
      reader.execute("SELECT * FROM entries")
      append_entry(database_path, "during-read")

      result = SqliteBackupService.new(
        environment: "test",
        role: :primary,
        database_path: database_path,
        backup_dir: backup_dir,
        clock: -> { FIXED_TIME },
        busy_timeout_ms: 50
      ).backup

      assert_equal "ok", result.integrity_check
      assert_equal [ "old", "during-read" ], read_entries(result.backup_path)
    ensure
      reader&.close unless reader&.closed?
      assert_equal [ "old", "during-read" ], read_entries(database_path) if database_path
    end
  end

  test "restore aborts when target writer lock is active" do
    with_tmpdir do |dir|
      database_path = dir.join("target.sqlite3")
      backup_path = dir.join("backup.sqlite3")
      create_database(database_path, [ "old" ])
      create_database(backup_path, [ "new" ])

      writer = SQLite3::Database.new(database_path.to_s)
      writer.execute("BEGIN IMMEDIATE")
      writer.execute("INSERT INTO entries (name) VALUES (?)", "uncommitted")

      assert_raises(SqliteBackupService::BackupError) do
        SqliteBackupService.new(
          environment: "test",
          role: :primary,
          database_path: database_path,
          backup_dir: dir.join("backups"),
          clock: -> { FIXED_TIME },
          busy_timeout_ms: 50,
          backup_retry_attempts: 1,
          backup_retry_delay: 0.01
        ).restore(backup_path, quiesced: true)
      end
    ensure
      writer&.execute("ROLLBACK") unless writer&.closed?
      writer&.close unless writer&.closed?
      assert_equal [ "old" ], read_entries(database_path) if database_path
    end
  end

  test "restore retries transient target writer lock" do
    with_tmpdir do |dir|
      database_path = dir.join("target.sqlite3")
      backup_path = dir.join("backup.sqlite3")
      create_database(database_path, [ "old" ])
      create_database(backup_path, [ "new" ])

      writer_ready = Queue.new
      writer_thread = Thread.new do
        writer = SQLite3::Database.new(database_path.to_s)
        writer.execute("BEGIN IMMEDIATE")
        writer.execute("INSERT INTO entries (name) VALUES (?)", "uncommitted")
        writer_ready << true
        sleep 0.05
        writer.execute("ROLLBACK")
      ensure
        writer&.close unless writer&.closed?
      end
      writer_ready.pop

      result = begin
        SqliteBackupService.new(
          environment: "test",
          role: :primary,
          database_path: database_path,
          backup_dir: dir.join("backups"),
          clock: -> { FIXED_TIME },
          busy_timeout_ms: 10,
          backup_retry_attempts: 10,
          backup_retry_delay: 0.02
        ).restore(backup_path, quiesced: true)
      ensure
        writer_thread.join
      end

      assert_equal "ok", result.integrity_check
      assert_equal [ "new" ], read_entries(database_path)
    end
  end

  test "backup rejects missing source database" do
    with_tmpdir do |dir|
      error = assert_raises(SqliteBackupService::MissingDatabaseError) do
        SqliteBackupService.new(
          environment: "test",
          role: :primary,
          database_path: dir.join("missing.sqlite3"),
          backup_dir: dir.join("backups"),
          clock: -> { FIXED_TIME }
        ).backup
      end

      assert_includes error.message, "Database file not found"
    end
  end

  test "configured database roles resolve from active record configuration" do
    with_tmpdir do |dir|
      service = SqliteBackupService.new(environment: "test", role: :queue, backup_dir: dir.join("backups"))

      assert_equal Rails.root.join("storage/test_queue.sqlite3").to_s, service.database_path.to_s
      assert_includes SqliteBackupService.configured_roles(environment: "test"), "primary"
      assert_includes SqliteBackupService.configured_roles(environment: "test"), "queue"
    end
  end

  test "unknown configured role is rejected" do
    error = assert_raises(SqliteBackupService::UnknownRoleError) do
      SqliteBackupService.new(environment: "test", role: :cache)
    end

    assert_includes error.message, "No database role 'cache'"
  end

  test "non sqlite configured role is rejected" do
    fake_config = Struct.new(:name, :adapter, :database).new("primary", "postgresql", "postgres://example")
    fake_configurations = Class.new do
      define_method(:configs_for) { |env_name:| [ fake_config ] }
    end.new

    error = assert_raises(SqliteBackupService::UnsupportedAdapterError) do
      SqliteBackupService.new(environment: "test", role: :primary, configurations: fake_configurations)
    end

    assert_includes error.message, "not sqlite3"
  end

  private

  def with_tmpdir
    Dir.mktmpdir do |dir|
      yield Pathname.new(dir)
    end
  end

  def create_database(path, entries)
    SQLite3::Database.new(path.to_s) do |database|
      database.execute("PRAGMA journal_mode = WAL")
      database.execute("CREATE TABLE entries (id INTEGER PRIMARY KEY, name TEXT NOT NULL)")
      entries.each { |entry| database.execute("INSERT INTO entries (name) VALUES (?)", entry) }
    end
  end

  def create_large_database(path, rows:)
    SQLite3::Database.new(path.to_s) do |database|
      database.execute("PRAGMA journal_mode = WAL")
      database.execute("CREATE TABLE large_entries (id INTEGER PRIMARY KEY, payload TEXT NOT NULL)")
      rows.times do
        database.execute("INSERT INTO large_entries (payload) VALUES (?)", "x" * 2_048)
      end
    end
  end

  def append_entry(path, entry)
    SQLite3::Database.new(path.to_s) do |database|
      database.execute("INSERT INTO entries (name) VALUES (?)", entry)
    end
  end

  def read_entries(path)
    database = SQLite3::Database.new(path.to_s, readonly: true)
    database.execute("SELECT name FROM entries ORDER BY id").flatten
  ensure
    database&.close unless database&.closed?
  end

  def large_entry_count(path)
    database = SQLite3::Database.new(path.to_s, readonly: true)
    database.get_first_value("SELECT COUNT(*) FROM large_entries")
  ensure
    database&.close unless database&.closed?
  end
end
