class AiTextParsingJob < ApplicationJob
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(parsing_session_id)
    parsing_session = ParsingSession.find(parsing_session_id)
    return unless parsing_session.pending?

    parsing_session.start!
    workspace = parsing_session.workspace

    begin
      parser = AiTextParser.new
      result = parser.parse(parsing_session.notes)

      # Incomplete rows (missing date/merchant/amount) are diverted to
      # ImportIssue instead of polluting the review queue. text_paste has
      # no processed_file so it stays nil per the ImportIssue contract.
      recorder = ImportIssueRecorder.new(
        parsing_session: parsing_session,
        source_type: "text_paste"
      )
      complete_rows, incomplete_count = recorder.split_and_record(result[:transactions] || [])

      stats = { total: complete_rows.size + incomplete_count, success: 0, duplicate: 0, error: incomplete_count }

      complete_rows.each do |tx_data|
        begin
          transaction = create_transaction(workspace, tx_data, parsing_session)

          match = DuplicateDetector.new(workspace, transaction).find_match
          if match
            parsing_session.duplicate_confirmations.create!(
              original_transaction: match.transaction,
              new_transaction: transaction,
              status: "pending",
              match_confidence: match.confidence,
              match_score: match.score
            )
            stats[:duplicate] += 1
          end

          stats[:success] += 1
        rescue StandardError => e
          Rails.logger.error "[AiTextParsingJob] Failed to create transaction: #{e.message}"
          stats[:error] += 1
        end
      end

      if stats[:total].zero? || stats[:success].zero?
        parsing_session.fail!
        create_failure_notifications(parsing_session)
      else
        parsing_session.complete!(stats)
        create_completion_notifications(parsing_session)
      end

    rescue AiTextParser::ApiError, AiTextParser::ParseError => e
      Rails.logger.error "[AiTextParsingJob] AI parsing failed: #{e.message}"
      parsing_session.fail!
      create_failure_notifications(parsing_session)
    rescue => e
      Rails.logger.error "[AiTextParsingJob] Unexpected error: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      parsing_session.fail!
      create_failure_notifications(parsing_session)
    end
  end

  private

  def create_transaction(workspace, tx_data, parsing_session)
    match = match_category(workspace, tx_data[:merchant])

    # institution is import/source metadata only — not a domain field.
    # Store the raw name from the parser in source_metadata; do NOT
    # look up a FinancialInstitution record or block on absence.
    metadata = build_source_metadata(tx_data)

    workspace.transactions.create!(
      date: tx_data[:date],
      merchant: tx_data[:merchant],
      amount: tx_data[:amount],
      payment_type: tx_data[:payment_type] || "lump_sum",
      installment_month: tx_data[:installment_month],
      installment_total: tx_data[:installment_total],
      category: match[:category],
      classification_source: match[:source],
      status: "pending_review",
      parsing_session: parsing_session,
      source_type: "text_paste",
      parse_confidence: tx_data[:confidence],
      source_metadata: metadata
    )
  end

  def build_source_metadata(tx_data)
    meta = { "source_channel" => "pasted_text" }
    meta["source_institution_raw"] = tx_data[:institution].strip if tx_data[:institution].present?
    meta["parser_confidence"] = tx_data[:confidence].to_f if tx_data[:confidence].present?
    meta
  end

  # ADR-0011 §Decision 3: 2단계 폴백(텍스트 경로)에서 어느 단계가 카테고리를
  # 결정했는지 함께 반환한다. classification_source 컬럼에 보존된다.
  # 반환: { category: Category|nil, source: "mapping_match"|"keyword_match"|nil }
  def match_category(workspace, merchant)
    return { category: nil, source: nil } if merchant.blank?

    mapping = CategoryMapping.find_for_merchant(workspace, merchant)
    return { category: mapping.category, source: "mapping_match" } if mapping

    keyword_category = workspace.categories.find { |c| c.matches?(merchant) }
    return { category: keyword_category, source: "keyword_match" } if keyword_category

    { category: nil, source: nil }
  end

  def create_failure_notifications(parsing_session)
    workspace = parsing_session.workspace

    if workspace.owner
      Notification.create_parsing_failed!(parsing_session, workspace.owner)
    end

    workspace.workspace_memberships.where(role: %w[co_owner member_write]).find_each do |membership|
      next if membership.user_id == workspace.owner_id
      Notification.create_parsing_failed!(parsing_session, membership.user)
    end
  end

  def create_completion_notifications(parsing_session)
    workspace = parsing_session.workspace

    if workspace.owner
      Notification.create_parsing_complete!(parsing_session, workspace.owner)
    end

    workspace.workspace_memberships.where(role: %w[co_owner member_write member_read]).find_each do |membership|
      next if membership.user_id == workspace.owner_id
      Notification.create_parsing_complete!(parsing_session, membership.user)
    end
  end
end
