class ImportReviewEventRecorder
  # Records an ImportReviewEvent. Logging failure must never block the user
  # action that triggered it; wrap callers safely. Returns the persisted event
  # on success, or nil on failure.
  #
  # changed_fields: array of field names the user actually touched (no raw
  # values — this is metric-only logging, not an audit log of values).
  def self.record(workspace:, parsing_session:, event_type:, reviewed_transaction: nil, changed_fields: [])
    ImportReviewEvent.create!(
      workspace: workspace,
      parsing_session: parsing_session,
      reviewed_transaction: reviewed_transaction,
      event_type: event_type,
      changed_fields: Array(changed_fields)
    )
  rescue StandardError => e
    Rails.logger.warn(
      "[ImportReviewEvent] record failed: type=#{event_type} session=#{parsing_session&.id} #{e.class}: #{e.message}"
    )
    nil
  end
end
