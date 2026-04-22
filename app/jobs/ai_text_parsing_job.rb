class AiTextParsingJob < ApplicationJob
  queue_as :default

  def perform(parsing_session_id)
    parsing_session = ParsingSession.find(parsing_session_id)
    return unless parsing_session.pending?

    parsing_session.start!
    workspace = parsing_session.workspace

    begin
      parser = AiTextParser.new
      result = parser.parse(parsing_session.notes)

      stats = { total: 0, success: 0, duplicate: 0, error: 0 }

      result[:transactions].each do |tx_data|
        next if tx_data[:is_cancel] # TODO: 취소 거래 매칭 로직 추후 구현

        stats[:total] += 1
        begin
          transaction = create_transaction(workspace, tx_data, parsing_session)

          duplicate = find_duplicate(workspace, transaction)
          if duplicate
            parsing_session.duplicate_confirmations.create!(
              original_transaction: duplicate,
              new_transaction: transaction,
              status: "pending"
            )
            stats[:duplicate] += 1
          end

          stats[:success] += 1
        rescue StandardError => e
          Rails.logger.error "[AiTextParsingJob] Failed to create transaction: #{e.message}"
          stats[:error] += 1
        end
      end

      if stats[:total].zero?
        parsing_session.fail!
      else
        parsing_session.complete!(stats)
        create_completion_notifications(parsing_session)
      end

    rescue AiTextParser::ApiError, AiTextParser::ParseError => e
      Rails.logger.error "[AiTextParsingJob] AI parsing failed: #{e.message}"
      parsing_session.fail!
    rescue => e
      Rails.logger.error "[AiTextParsingJob] Unexpected error: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      parsing_session.fail!
    end
  end

  private

  def create_transaction(workspace, tx_data, parsing_session)
    institution = find_institution(tx_data[:institution])
    category = match_category(workspace, tx_data[:merchant])

    workspace.transactions.create!(
      date: tx_data[:date],
      merchant: tx_data[:merchant],
      amount: tx_data[:amount],
      payment_type: tx_data[:payment_type] || "lump_sum",
      installment_month: tx_data[:installment_month],
      installment_total: tx_data[:installment_total],
      financial_institution: institution,
      category: category,
      status: "pending_review",
      parsing_session: parsing_session,
      source_type: "text_paste",
      parse_confidence: tx_data[:confidence]
    )
  end

  def find_institution(name)
    return nil if name.blank?
    sanitized = ActiveRecord::Base.sanitize_sql_like(name)
    FinancialInstitution.find_by("name LIKE ?", "%#{sanitized}%")
  end

  def match_category(workspace, merchant)
    return nil if merchant.blank?

    mapping = CategoryMapping.find_for_merchant(workspace, merchant)
    return mapping.category if mapping

    workspace.categories.find { |c| c.matches?(merchant) }
  end

  def find_duplicate(workspace, transaction)
    workspace.transactions
             .active
             .where(date: transaction.date, amount: transaction.amount)
             .where.not(id: transaction.id)
             .where(installment_month: nil)
             .first
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
