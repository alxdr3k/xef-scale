class ImportIssueRecorder
  # Splits parsed tx_data rows into complete vs incomplete and persists an
  # ImportIssue(missing_required_fields) for each incomplete row. Failure to
  # persist must not block the parse job — log and continue.

  def initialize(parsing_session:, source_type:, processed_file: nil)
    @parsing_session = parsing_session
    @source_type = source_type
    @processed_file = processed_file
  end

  # Returns [complete_rows, recorded_count, failed_count]
  # - recorded_count: ImportIssues actually persisted (incomplete row recovered)
  # - failed_count: incomplete rows we could not persist (silent data loss)
  def split_and_record(rows)
    incomplete, complete = rows.partition { |row| missing_fields_for(row).any? }
    recorded = 0
    failed = 0
    incomplete.each do |row|
      record_incomplete(row) ? recorded += 1 : failed += 1
    end
    [ complete, recorded, failed ]
  end

  private

  def missing_fields_for(row)
    ImportIssue::REQUIRED_FIELDS.select do |field|
      value = fetch(row, field)
      value.blank? || (field == "amount" && value.to_i == 0)
    end
  end

  def record_incomplete(row)
    missing = missing_fields_for(row)
    return false if missing.empty?

    @parsing_session.import_issues.create!(
      workspace: @parsing_session.workspace,
      processed_file: @processed_file,
      source_type: @source_type,
      date: fetch(row, "date"),
      merchant: fetch(row, "merchant").presence,
      amount: fetch(row, "amount"),
      missing_fields: missing,
      raw_payload: payload_for(row)
    )
    true
  rescue ActiveRecord::ActiveRecordError => e
    Rails.logger.warn(
      "[ImportIssueRecorder] failed to record incomplete row " \
      "(session=#{@parsing_session.id}, source=#{@source_type}): #{e.class}: #{e.message}"
    )
    false
  end

  def fetch(row, field)
    row[field.to_sym] || row[field.to_s]
  end

  def payload_for(row)
    row.to_h.transform_keys(&:to_s).transform_values do |v|
      v.respond_to?(:iso8601) ? v.iso8601 : v
    end
  end
end
