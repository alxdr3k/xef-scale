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

  # Only normalize fields the caller actually submitted. PATCH semantics:
  # an omitted key must NOT overwrite the persisted value with nil.
  def pick_submitted(attrs)
    raw = attrs.to_h.symbolize_keys
    out = {}
    out[:date] = normalize_date(raw[:date]) if raw.key?(:date)
    if raw.key?(:merchant)
      out[:merchant] = raw[:merchant].is_a?(String) ? raw[:merchant].strip.presence : raw[:merchant]
    end
    out[:amount] = normalize_amount(raw[:amount]) if raw.key?(:amount)
    out
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
