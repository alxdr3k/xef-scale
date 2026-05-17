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
    return failure("이미 처리된 항목입니다.") unless @issue.open?
    return failure("필수값 누락 항목만 수정할 수 있습니다.") unless @issue.missing_required_fields?

    normalized = normalize(attributes)
    remaining = missing_fields_for(normalized)

    if remaining.any?
      # Partial submission — keep the issue open with whatever the user typed
      # and tell them which fields are still required.
      @issue.assign_attributes(normalized.merge(missing_fields: remaining))
      unless @issue.valid?
        return failure(@issue.errors.full_messages.to_sentence.presence || "수정값을 확인해 주세요.")
      end
      @issue.save!
      return Result.new(status: :updated, message: "수정값을 저장했습니다. 남은 필수값을 채워 주세요.")
    end

    @issue.assign_attributes(normalized.merge(missing_fields: []))
    promote_completed_issue!
  end

  def dismiss!
    return failure("이미 처리된 항목입니다.") unless @issue.open?

    @issue.update!(status: "dismissed")
    Result.new(status: :dismissed, message: "수정 필요 항목을 제외했습니다.")
  end

  private

  def promote_completed_issue!
    candidate = @workspace.transactions.build(
      date: @issue.date,
      merchant: @issue.merchant,
      amount: @issue.amount,
      status: "pending_review",
      parsing_session: @issue.parsing_session,
      source_type: @issue.source_type
    )

    ActiveRecord::Base.transaction do
      candidate.save!
      @issue.update!(
        status: "resolved",
        resolved_transaction: candidate,
        missing_fields: []
      )
    end

    Result.new(status: :promoted, message: "결제 내역에 반영했습니다.", transaction: candidate)
  rescue ActiveRecord::RecordInvalid => e
    failure(e.record.errors.full_messages.to_sentence.presence || e.message)
  end

  def normalize(attrs)
    raw = attrs.to_h.symbolize_keys.slice(:date, :merchant, :amount)
    {
      date: normalize_date(raw[:date]),
      merchant: raw[:merchant].is_a?(String) ? raw[:merchant].strip.presence : raw[:merchant],
      amount: normalize_amount(raw[:amount])
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
