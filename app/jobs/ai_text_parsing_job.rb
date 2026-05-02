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

      stats = { total: 0, success: 0, duplicate: 0, error: 0 }
      duplicate_policy = ImportDuplicatePolicy.new(
        workspace: workspace,
        parsing_session: parsing_session,
        source_type: "text_paste"
      )

      result[:transactions].each do |tx_data|
        stats[:total] += 1
        begin
          transaction = create_transaction(workspace, tx_data, parsing_session)

          duplicate_result = duplicate_policy.apply(transaction, raw_payload: tx_data)
          unless duplicate_result.no_duplicate?
            stats[:duplicate] += 1
            next
          end

          stats[:success] += 1
        rescue StandardError => e
          Rails.logger.error "[AiTextParsingJob] Failed to create transaction: #{e.message}"
          stats[:error] += 1
        end
      end

      has_import_exceptions = stats[:error].positive? || parsing_session.open_import_issues.exists?

      if parsing_failed_without_import_outcome?(stats, parsing_session)
        parsing_session.update!(
          total_count: stats[:total],
          success_count: stats[:success],
          duplicate_count: stats[:duplicate],
          error_count: stats[:error]
        )
        parsing_session.fail!
        create_failure_notifications(parsing_session)
      else
        committed_transactions = parsing_session.auto_commit_ready_transactions!(
          has_import_exceptions: has_import_exceptions
        )
        parsing_session.complete!(stats)
        create_success_side_effects(parsing_session, workspace, committed_transactions)
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
    category = match_category(workspace, tx_data[:merchant])

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
      category: category,
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

  def match_category(workspace, merchant)
    return nil if merchant.blank?

    mapping = CategoryMapping.find_for_merchant(workspace, merchant)
    return mapping.category if mapping

    workspace.categories.find { |c| c.matches?(merchant) }
  end

  def parsing_failed_without_import_outcome?(stats, parsing_session)
    return true if stats[:total].zero?
    return true if stats[:success].zero? && stats[:error].positive? && !parsing_session.open_import_issues.exists?

    stats[:success].zero? &&
      stats[:duplicate].zero? &&
      !parsing_session.open_import_issues.exists?
  end

  def create_success_side_effects(parsing_session, workspace, committed_transactions)
    create_budget_alerts(workspace, committed_transactions)
    create_completion_notifications_safely(parsing_session)
    create_import_repair_notifications_safely(parsing_session)
  end

  def create_budget_alerts(workspace, committed_transactions)
    BudgetAlertService.create_for_transactions!(workspace, committed_transactions)
  rescue StandardError => e
    Rails.logger.error "[AiTextParsingJob] Budget alert side effect failed: #{e.message}"
  end

  def create_completion_notifications_safely(parsing_session)
    create_completion_notifications(parsing_session)
  rescue StandardError => e
    Rails.logger.error "[AiTextParsingJob] Completion notification side effect failed: #{e.message}"
  end

  def create_import_repair_notifications_safely(parsing_session)
    create_import_repair_notifications(parsing_session)
  rescue StandardError => e
    Rails.logger.error "[AiTextParsingJob] Import repair notification side effect failed: #{e.message}"
  end

  def create_import_repair_notifications(parsing_session)
    ImportRepairNotifier.call(parsing_session)
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
