class ImportDuplicatePolicy
  Result = Struct.new(:action, :match, keyword_init: true) do
    def no_duplicate?
      action == :no_duplicate
    end

    def skipped_exact_duplicate?
      action == :skipped_exact_duplicate
    end

    def repair_issue?
      action == :repair_issue
    end
  end

  def initialize(workspace:, parsing_session:, source_type:, processed_file: nil)
    @workspace = workspace
    @parsing_session = parsing_session
    @source_type = source_type
    @processed_file = processed_file
  end

  def self.exact_duplicate?(transaction, candidate)
    transaction.date == candidate.date &&
      transaction.amount == candidate.amount &&
      normalized_merchant(transaction.merchant) == normalized_merchant(candidate.merchant) &&
      transaction.payment_type == candidate.payment_type &&
      transaction.installment_month == candidate.installment_month &&
      transaction.installment_total == candidate.installment_total &&
      transaction.original_amount == candidate.original_amount
  end

  def self.normalized_merchant(value)
    value.to_s.strip.gsub(/\s+/, "").downcase
  end

  def apply(transaction, raw_payload: {})
    same_session_duplicate = same_session_exact_duplicate(transaction)
    if same_session_duplicate
      transaction.destroy!
      return Result.new(
        action: :skipped_exact_duplicate,
        match: DuplicateDetector::Match.new(
          transaction: same_session_duplicate,
          score: 100,
          confidence: DuplicateDetector::CONFIDENCE_HIGH
        )
      )
    end

    match = DuplicateDetector.new(@workspace, transaction).find_match
    return Result.new(action: :no_duplicate) unless match

    if exact_duplicate?(transaction, match.transaction)
      transaction.destroy!
      Result.new(action: :skipped_exact_duplicate, match: match)
    else
      ActiveRecord::Base.transaction do
        create_ambiguous_duplicate_issue!(transaction, match, raw_payload: raw_payload)
        transaction.destroy!
      end
      Result.new(action: :repair_issue, match: match)
    end
  end

  private

  def same_session_exact_duplicate(transaction)
    # Scoped to pending_review: at call time all same-session staging rows are still
    # pending_review (auto_commit_ready_transactions! runs after all rows are processed).
    @parsing_session.transactions
                    .pending_review
                    .where(deleted: false)
                    .where.not(id: transaction.id)
                    .detect { |candidate| exact_duplicate?(transaction, candidate) }
  end

  def exact_duplicate?(transaction, candidate)
    self.class.exact_duplicate?(transaction, candidate)
  end

  def normalized_merchant(value)
    self.class.normalized_merchant(value)
  end

  def create_ambiguous_duplicate_issue!(transaction, match, raw_payload:)
    @parsing_session.import_issues.create!(
      workspace: @workspace,
      processed_file: @processed_file,
      duplicate_transaction: match.transaction,
      source_type: @source_type,
      issue_type: "ambiguous_duplicate",
      date: transaction.date,
      merchant: transaction.merchant,
      amount: transaction.amount,
      missing_fields: [],
      raw_payload: issue_payload(transaction, match, raw_payload)
    )
  end

  def issue_payload(transaction, match, raw_payload)
    serialize_payload(raw_payload).merge(
      "issue_type" => "ambiguous_duplicate",
      "duplicate_match" => {
        "transaction_id" => match.transaction.id,
        "date" => match.transaction.date&.iso8601,
        "merchant" => match.transaction.merchant,
        "amount" => match.transaction.amount,
        "score" => match.score,
        "confidence" => match.confidence
      },
      "candidate" => {
        "date" => transaction.date&.iso8601,
        "merchant" => transaction.merchant,
        "amount" => transaction.amount
      }
    )
  end

  def serialize_payload(payload)
    payload.to_h.transform_keys(&:to_s).transform_values do |value|
      value.respond_to?(:iso8601) ? value.iso8601 : value
    end
  end
end
