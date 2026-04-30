# frozen_string_literal: true

require "sqlite3"

class SqliteBackupService
  DEFAULT_BACKUP_DIR = Rails.root.join("storage", "sqlite_backups").freeze
  SQLITE_ADAPTER = "sqlite3"
  SQLITE_MAIN_DATABASE = "main"
  BACKUP_STEP_PAGES = 100
  INTEGRITY_OK = "ok"
  RETRIABLE_BACKUP_STATUSES = [
    SQLite3::Constants::ErrorCode::BUSY,
    SQLite3::Constants::ErrorCode::LOCKED
  ].freeze

  BackupResult = Struct.new(
    :environment,
    :role,
    :database_path,
    :backup_path,
    :integrity_check,
    :bytes,
    keyword_init: true
  )

  RestoreResult = Struct.new(
    :environment,
    :role,
    :database_path,
    :backup_path,
    :integrity_check,
    :bytes,
    keyword_init: true
  )

  class Error < StandardError; end
  class MissingDatabaseError < Error; end
  class MissingBackupError < Error; end
  class UnknownRoleError < Error; end
  class UnsupportedAdapterError < Error; end
  class IntegrityError < Error; end
  class RestoreRequiresQuiescenceError < Error; end
  class BackupError < Error; end

  attr_reader :environment, :role, :database_path, :backup_dir

  def self.configured_roles(environment: Rails.env)
    ActiveRecord::Base.configurations.configs_for(env_name: environment.to_s)
                      .select { |config| config.adapter == SQLITE_ADAPTER }
                      .map(&:name)
                      .sort
  end

  def initialize(
    environment: Rails.env,
    role: :primary,
    database_path: nil,
    backup_dir: DEFAULT_BACKUP_DIR,
    clock: -> { Time.current },
    configurations: ActiveRecord::Base.configurations,
    busy_timeout_ms: 5_000,
    backup_retry_attempts: 5,
    backup_retry_delay: 0.05,
    backup_max_steps: 10_000
  )
    @environment = environment.to_s
    @role = role.to_s
    @backup_dir = Pathname.new(backup_dir.to_s)
    @configurations = configurations
    @database_path = database_path ? absolute_path(database_path) : configured_database_path
    @clock = clock
    @busy_timeout_ms = busy_timeout_ms
    @backup_retry_attempts = backup_retry_attempts
    @backup_retry_delay = backup_retry_delay
    @backup_max_steps = backup_max_steps
  end

  def backup(label: nil)
    raise MissingDatabaseError, "Database file not found: #{database_path}" unless File.file?(database_path)

    FileUtils.mkdir_p(backup_dir)
    checkpoint_source_for_backup(database_path)

    backup_path = next_backup_path(label)
    copy_database(source_path: database_path, destination_path: backup_path)
    integrity = integrity_check!(backup_path)

    BackupResult.new(
      environment: environment,
      role: role,
      database_path: database_path.to_s,
      backup_path: backup_path.to_s,
      integrity_check: integrity,
      bytes: File.size(backup_path)
    )
  rescue StandardError
    FileUtils.rm_f(backup_path) if defined?(backup_path) && backup_path && File.exist?(backup_path)
    raise
  end

  def restore(backup_path, quiesced: false)
    source_path = Pathname.new(backup_path.to_s)
    raise MissingBackupError, "Backup file not found: #{source_path}" unless File.file?(source_path)

    validate_restore_quiescence!(quiesced)
    integrity_check!(source_path)
    FileUtils.mkdir_p(database_path.dirname)
    copy_database(source_path: source_path, destination_path: database_path)
    integrity = integrity_check!(database_path)

    RestoreResult.new(
      environment: environment,
      role: role,
      database_path: database_path.to_s,
      backup_path: source_path.to_s,
      integrity_check: integrity,
      bytes: File.size(database_path)
    )
  end

  def integrity_check!(path = database_path)
    result = with_database(path, readonly: true) do |database|
      database.execute("PRAGMA integrity_check").flatten
    end

    return INTEGRITY_OK if result == [ INTEGRITY_OK ]

    raise IntegrityError, "SQLite integrity_check failed for #{path}: #{result.join(', ')}"
  rescue SQLite3::Exception => e
    raise IntegrityError, "SQLite integrity_check failed for #{path}: #{e.message}"
  end

  private

  def configured_database_path
    config = @configurations.configs_for(env_name: environment)
                            .find { |candidate| candidate.name == role }

    raise UnknownRoleError, "No database role '#{role}' is configured for #{environment}" unless config

    unless config.adapter == SQLITE_ADAPTER
      raise UnsupportedAdapterError,
            "Database role '#{role}' for #{environment} uses #{config.adapter}, not sqlite3"
    end

    absolute_path(config.database)
  end

  def absolute_path(path)
    pathname = Pathname.new(path.to_s)
    pathname.absolute? ? pathname : Rails.root.join(pathname)
  end

  def copy_database(source_path:, destination_path:)
    with_database_pair(source_path, destination_path) do |source, destination|
      backup = SQLite3::Backup.new(destination, SQLITE_MAIN_DATABASE, source, SQLITE_MAIN_DATABASE)
      run_backup_steps(backup, source_path, destination_path)
    rescue SQLite3::Exception => e
      raise BackupError, "SQLite backup failed from #{source_path} to #{destination_path}: #{e.message}"
    ensure
      backup&.finish
    end
  end

  def run_backup_steps(backup, source_path, destination_path)
    attempts = 0
    steps = 0

    loop do
      steps += 1
      if steps > @backup_max_steps
        raise BackupError,
              "SQLite backup exceeded #{@backup_max_steps} steps from #{source_path} to #{destination_path}"
      end

      status = backup.step(BACKUP_STEP_PAGES)
      return if status == SQLite3::Constants::ErrorCode::DONE

      if status == SQLite3::Constants::ErrorCode::OK
        attempts = 0
        next
      end

      if RETRIABLE_BACKUP_STATUSES.include?(status) && attempts < @backup_retry_attempts
        attempts += 1
        sleep @backup_retry_delay
        next
      end

      raise BackupError,
            "SQLite backup step failed from #{source_path} to #{destination_path} with status #{status}"
    end
  end

  def checkpoint_source_for_backup(path)
    result = with_database(path) do |database|
      database.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    end
    busy, log_frames, checkpointed_frames = result.first&.map(&:to_i)

    return if busy&.zero?

    Rails.logger.warn(
      "SQLite WAL checkpoint was busy for #{path}; continuing online backup: " \
      "log=#{log_frames}, checkpointed=#{checkpointed_frames}"
    )
  end

  def validate_restore_quiescence!(quiesced)
    return if quiesced

    raise RestoreRequiresQuiescenceError,
          "SQLite restore requires all app and worker DB access to be quiesced; pass quiesced: true after draining connections"
  end

  def next_backup_path(label)
    basename = [
      environment,
      role,
      "sqlite_backup",
      @clock.call.strftime("%Y%m%d_%H%M%S"),
      sanitized_label(label)
    ].compact.join("_")
    candidate = backup_dir.join("#{basename}.sqlite3")
    counter = 1

    while File.exist?(candidate)
      counter += 1
      candidate = backup_dir.join("#{basename}_#{counter}.sqlite3")
    end

    candidate
  end

  def sanitized_label(label)
    return nil if label.blank?

    sanitized = label.to_s.gsub(/[^a-zA-Z0-9_-]+/, "_").gsub(/\A_+|_+\z/, "")
    sanitized.presence
  end

  def with_database(path, **options)
    database = SQLite3::Database.new(path.to_s, **options)
    database.busy_timeout = @busy_timeout_ms
    yield database
  ensure
    database&.close unless database&.closed?
  end

  def with_database_pair(source_path, destination_path)
    source = SQLite3::Database.new(source_path.to_s, readonly: true)
    destination = SQLite3::Database.new(destination_path.to_s)
    source.busy_timeout = @busy_timeout_ms
    destination.busy_timeout = @busy_timeout_ms
    yield source, destination
  ensure
    source&.close unless source&.closed?
    destination&.close unless destination&.closed?
  end
end
