class ImportIssueResolutionService
  Result = Struct.new(:status, :message, :transaction, keyword_init: true) do
    def success?
      %i[updated promoted dismissed exact_duplicate_skipped ambiguous_duplicate].include?(status)
    end

    def promoted?
      status == :promoted
    end

    # True only when a new Transaction was actually committed to the ledger.
    # success? can be true even when no transaction was created (e.g. :ambiguous_duplicate
    # keeps the issue open for a duplicate decision).
    def transaction_committed?
      status == :promoted
    end
  end

  def initialize(import_issue, user:)
    @issue = import_issue
    @workspace = import_issue.workspace
    @user = user
  end

  def update_missing_fields!(attributes)
    return failure("이미 처리된 항목입니다.") unless @issue.open?
    return failure("필수값 누락 항목만 수정할 수 있습니다.") unless @issue.missing_required_fields?

    normalized = normalized_attributes(attributes)
    missing_fields = missing_fields_for(normalized)

    if missing_fields.any?
      @issue.assign_attributes(normalized.merge(missing_fields: missing_fields))
      return failure(@issue.errors.full_messages.to_sentence.presence || "수정값을 확인해 주세요.") unless @issue.valid?

      @issue.save!
      return Result.new(status: :updated, message: "수정값을 저장했습니다. 남은 필수값을 채워 주세요.")
    end

    @issue.assign_attributes(normalized.merge(missing_fields: []))
    promote_completed_issue!(force_duplicate: false)
  end

  def promote_as_new!
    return failure("이미 처리된 항목입니다.") unless @issue.open?
    return failure("중복 확인 항목만 새 거래로 등록할 수 있습니다.") unless @issue.ambiguous_duplicate?

    promote_completed_issue!(force_duplicate: true)
  end

  def dismiss!
    return failure("이미 처리된 항목입니다.") unless @issue.open?

    @issue.update!(
      status: "dismissed",
      raw_payload: payload_with_resolution("dismissed")
    )
    resolve_repair_notifications!
    Result.new(status: :dismissed, message: "수정 필요 항목을 제외했습니다.")
  end

  private

  def promote_completed_issue!(force_duplicate:)
    candidate = build_transaction

    unless force_duplicate
      duplicate_result = handle_duplicate_for(candidate)
      return duplicate_result if duplicate_result
    end

    ActiveRecord::Base.transaction do
      candidate.save!
      candidate.commit!(@user)
      @issue.update!(
        status: "resolved",
        resolved_transaction: candidate,
        missing_fields: [],
        raw_payload: payload_with_resolution("promoted", transaction_id: candidate.id)
      )
    end

    begin
      BudgetAlertService.create_for_transactions!(@workspace, [ candidate ])
    rescue StandardError => e
      Rails.logger.error "[ImportIssueResolution] Budget alert failed: #{e.message}"
    end
    resolve_repair_notifications!
    Result.new(status: :promoted, message: "결제 내역에 반영했습니다.", transaction: candidate)
  rescue ActiveRecord::RecordInvalid => e
    failure(e.record.errors.full_messages.to_sentence.presence || e.message)
  end

  def handle_duplicate_for(candidate)
    match = DuplicateDetector.new(@workspace, candidate).find_match
    return nil unless match

    if ImportDuplicatePolicy.exact_duplicate?(candidate, match.transaction)
      @issue.update!(
        status: "dismissed",
        missing_fields: [],
        raw_payload: payload_with_resolution(
          "exact_duplicate_skipped",
          duplicate_transaction_id: match.transaction.id,
          duplicate_score: match.score,
          duplicate_confidence: match.confidence
        )
      )
      resolve_repair_notifications!
      return Result.new(status: :exact_duplicate_skipped, message: "이미 등록된 동일 결제라 제외했습니다.")
    end

    @issue.update!(
      issue_type: "ambiguous_duplicate",
      duplicate_transaction: match.transaction,
      missing_fields: [],
      raw_payload: payload_with_resolution(
        "ambiguous_duplicate",
        duplicate_transaction_id: match.transaction.id,
        duplicate_score: match.score,
        duplicate_confidence: match.confidence
      )
    )
    Result.new(status: :ambiguous_duplicate, message: "비슷한 결제가 있어 중복 확인 항목으로 전환했습니다.")
  end

  def build_transaction
    @workspace.transactions.build(
      date: @issue.date,
      merchant: @issue.merchant.to_s.strip,
      amount: @issue.amount,
      description: raw_value("description", "notes"),
      category: matched_category,
      parsing_session: @issue.parsing_session,
      source_type: @issue.source_type,
      status: "pending_review",
      payment_type: payment_type,
      installment_month: integer_raw_value("installment_month"),
      installment_total: integer_raw_value("installment_total"),
      parse_confidence: numeric_raw_value("confidence", "parse_confidence"),
      source_metadata: source_metadata
    )
  end

  def matched_category
    CategoryMapping.find_category_for_merchant_and_description(
      @workspace,
      @issue.merchant.to_s.strip,
      raw_value("description", "notes")
    )
  end

  def source_metadata
    channel = @issue.image_upload? ? "screenshot_repair" : "text_repair"
    metadata = {
      "source_channel" => channel,
      "import_issue_id" => @issue.id
    }
    raw_institution = raw_value("source_institution_raw")
    metadata["source_institution_raw"] = raw_institution if raw_institution.present?
    confidence = numeric_raw_value("confidence", "parse_confidence")
    metadata["parser_confidence"] = confidence if confidence
    metadata
  end

  def normalized_attributes(attributes)
    {
      date: normalized_date(attributes[:date]),
      merchant: attributes[:merchant].to_s.strip.presence,
      amount: normalized_amount(attributes[:amount])
    }
  end

  def missing_fields_for(attributes)
    ImportIssue::REQUIRED_FIELDS.select do |field|
      value = attributes[field.to_sym]
      value.blank? || (field == "amount" && value.to_i == 0)
    end
  end

  def normalized_date(value)
    return value if value.is_a?(Date)
    return nil if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def normalized_amount(value)
    return value if value.is_a?(Integer)
    return nil if value.blank?

    Integer(value.to_s.delete(","), exception: false)
  end

  def payment_type
    raw = raw_value("payment_type").presence
    Transaction::PAYMENT_TYPES.include?(raw) ? raw : "lump_sum"
  end

  def raw_value(*keys)
    keys.each do |key|
      value = raw_payload[key.to_s]
      return value if value.present?
    end
    nil
  end

  def raw_payload
    (@issue.raw_payload || {}).to_h
  end

  def integer_raw_value(*keys)
    raw = raw_value(*keys)
    return nil if raw.blank?

    Integer(raw, exception: false)
  end

  def numeric_raw_value(*keys)
    raw = raw_value(*keys)
    return nil if raw.blank?

    Float(raw, exception: false)
  end

  def payload_with_resolution(resolution, extras = {})
    raw_payload.merge(
      "repair_resolution" => extras.merge(
        resolution: resolution,
        resolved_by_id: @user&.id,
        resolved_at: Time.current.iso8601
      )
    )
  end

  def resolve_repair_notifications!
    return if @issue.parsing_session.open_import_issues.exists?

    Notification.where(
      workspace: @workspace,
      notifiable: @issue.parsing_session,
      notification_type: "import_repair_needed",
      read_at: nil
    ).update_all(read_at: Time.current, updated_at: Time.current)
  end

  def failure(message)
    Result.new(status: :invalid, message: message.presence || "수정값을 확인해 주세요.")
  end
end
