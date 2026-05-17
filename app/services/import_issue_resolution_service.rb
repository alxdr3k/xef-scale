class ImportIssueResolutionService
  Result = Struct.new(:status, :message, :transaction, keyword_init: true) do
    def success?
      %i[updated promoted dismissed].include?(status)
    end
  end

  def initialize(import_issue, user:)
    @issue = import_issue
    @workspace = import_issue.workspace
    @user = user
  end

  def update_missing_fields!(attributes)
    return failure("필수값 누락 항목만 수정할 수 있습니다.") unless @issue.missing_required_fields?

    submitted = pick_submitted(attributes)
    return failure("수정할 값을 입력해 주세요.") if submitted.empty?

    # Lock session first (consistent ordering with commit_all!/rollback_all!),
    # then the issue. Re-verify state inside the locked transaction so a
    # concurrent commit/discard cannot flip review_status between the guard
    # and the mutation.
    ActiveRecord::Base.transaction do
      session = @issue.parsing_session
      session&.lock!
      return failure("이 가져오기는 이미 마감되어 수리할 수 없습니다.") unless session&.review_pending?

      @issue.lock!
      return failure("이미 처리된 항목입니다.") unless @issue.open?

      merged = submitted_with_existing(submitted)
      remaining = missing_fields_for(merged)

      if remaining.any?
        @issue.assign_attributes(submitted.merge(missing_fields: remaining))
        unless @issue.valid?
          return failure(@issue.errors.full_messages.to_sentence.presence || "수정값을 확인해 주세요.")
        end
        @issue.save!
        return Result.new(status: :updated, message: "수정값을 저장했습니다. 남은 필수값을 채워 주세요.")
      end

      @issue.assign_attributes(submitted.merge(missing_fields: []))
      return promote_completed_issue!
    end
  rescue ActiveRecord::RecordInvalid => e
    # Let the transaction roll back first; then surface the message as a
    # failure Result so the partial candidate transaction does not leak.
    failure(e.record.errors.full_messages.to_sentence.presence || e.message)
  end

  def dismiss!
    ActiveRecord::Base.transaction do
      session = @issue.parsing_session
      session&.lock!
      return failure("이 가져오기는 이미 마감되어 수리할 수 없습니다.") unless session&.review_pending?

      @issue.lock!
      return failure("이미 처리된 항목입니다.") unless @issue.open?

      @issue.update!(status: "dismissed")
    end
    Result.new(status: :dismissed, message: "수정 필요 항목을 제외했습니다.")
  end

  private

  def promote_completed_issue!
    candidate = @workspace.transactions.build(transaction_attrs_for_promotion)
    candidate.save!
    # Run the same duplicate detection the parse jobs run so repaired rows
    # cannot bypass the duplicate-review guard. A match becomes a pending
    # DuplicateConfirmation that the user must resolve before commit_all!.
    match = DuplicateDetector.new(@workspace, candidate).find_match
    if match
      @issue.parsing_session.duplicate_confirmations.create!(
        original_transaction: match.transaction,
        new_transaction: candidate,
        status: "pending",
        match_confidence: match.confidence,
        match_score: match.score
      )
    end

    @issue.update!(
      status: "resolved",
      resolved_transaction: candidate,
      missing_fields: []
    )

    Result.new(status: :promoted, message: "결제 내역에 반영했습니다.", transaction: candidate)
  end

  # Only normalize fields the caller actually submitted with a real value.
  # Browser forms always include the date/merchant/amount keys even when
  # blank, so we treat blank input as "not submitted" — keeping the persisted
  # value untouched (matches PATCH-omitted semantics). Repair never needs to
  # explicitly clear a value to nil.
  def pick_submitted(attrs)
    raw = attrs.to_h.symbolize_keys
    out = {}

    if raw.key?(:date)
      date = normalize_date(raw[:date])
      out[:date] = date if date.present?
    end

    if raw.key?(:merchant)
      merchant = raw[:merchant].is_a?(String) ? raw[:merchant].strip.presence : raw[:merchant]
      out[:merchant] = merchant if merchant.present?
    end

    if raw.key?(:amount)
      amount = normalize_amount(raw[:amount])
      out[:amount] = amount if amount.present? && amount.to_i != 0
    end

    out
  end

  # Build the attribute set for the promoted transaction. We start from the
  # parser's original tx_data captured in raw_payload (so installment metadata,
  # source_metadata, payment_type, etc. survive repair), then overlay the
  # user-supplied date/merchant/amount and apply the same category match the
  # parse jobs would have run if the row had been complete in the first place.
  def transaction_attrs_for_promotion
    payload = (@issue.raw_payload || {}).with_indifferent_access
    match = match_category(@issue.merchant, amount: @issue.amount)

    {
      date: @issue.date,
      merchant: @issue.merchant,
      amount: @issue.amount,
      description: payload[:description].presence || "",
      payment_type: payload[:payment_type].presence || "lump_sum",
      installment_month: payload[:installment_month],
      installment_total: payload[:installment_total],
      status: "pending_review",
      parsing_session: @issue.parsing_session,
      source_type: @issue.source_type,
      category: match[:category],
      classification_source: match[:source],
      source_metadata: source_metadata_for(payload),
      parse_confidence: payload[:parser_confidence] || payload[:confidence]
    }
  end

  # Mirror FileParsingJob/AiTextParsingJob#match_category — pass amount so
  # amount-specific CategoryMapping rules apply to repaired rows too.
  def match_category(merchant, amount: nil)
    return { category: nil, source: nil } if merchant.blank?

    mapping = CategoryMapping.find_for_merchant(@workspace, merchant, amount: amount)
    return { category: mapping.category, source: "mapping_match" } if mapping

    keyword_category = @workspace.categories.find { |c| c.matches?(merchant) }
    return { category: keyword_category, source: "keyword_match" } if keyword_category

    { category: nil, source: nil }
  end

  def source_metadata_for(payload)
    meta = {}
    # Match the existing parse-job convention: image path uses "screenshot",
    # text paste uses "pasted_text". Analytics consumers split on this.
    meta["source_channel"] = @issue.text_paste? ? "pasted_text" : "screenshot"
    if (raw = payload[:source_institution_raw] || payload[:institution]).present?
      meta["source_institution_raw"] = raw.to_s.strip
    end
    if (raw_app = payload[:source_app_raw]).present?
      meta["source_app_raw"] = raw_app.to_s
    end
    if (conf = payload[:parser_confidence] || payload[:confidence]).present?
      meta["parser_confidence"] = conf.to_f
    end
    meta
  end

  def submitted_with_existing(submitted)
    {
      date: submitted.key?(:date) ? submitted[:date] : @issue.date,
      merchant: submitted.key?(:merchant) ? submitted[:merchant] : @issue.merchant,
      amount: submitted.key?(:amount) ? submitted[:amount] : @issue.amount
    }
  end


  def normalize_date(value)
    return value if value.is_a?(Date)
    return nil if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def normalize_amount(value)
    return value if value.is_a?(Integer)
    return nil if value.blank?

    Integer(value.to_s, exception: false)
  end

  def missing_fields_for(normalized)
    ImportIssue::REQUIRED_FIELDS.select do |field|
      value = normalized[field.to_sym]
      value.blank? || (field == "amount" && value.to_i == 0)
    end
  end

  def failure(message)
    Result.new(status: :failed, message: message)
  end
end
