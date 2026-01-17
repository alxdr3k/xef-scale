require 'open3'

class FileParsingJob < ApplicationJob
  queue_as :default

  def perform(processed_file_id)
    processed_file = ProcessedFile.find(processed_file_id)
    processed_file.mark_processing!

    parsing_session = processed_file.create_parsing_session!(
      workspace_id: processed_file.workspace_id,
      status: 'processing',
      review_status: 'pending_review'
    )
    parsing_session.start!

    begin
      result = parse_file(processed_file)

      # Create transactions
      stats = { total: result.size, success: 0, duplicate: 0, error: 0 }

      result.each do |tx_data|
        begin
          transaction = create_transaction(processed_file.workspace, tx_data, parsing_session)

          # Check for duplicates (only against committed transactions)
          duplicate = find_duplicate(processed_file.workspace, transaction)
          if duplicate
            parsing_session.duplicate_confirmations.create!(
              original_transaction: duplicate,
              new_transaction: transaction,
              status: 'pending'
            )
            stats[:duplicate] += 1
          end

          stats[:success] += 1
        rescue StandardError => e
          Rails.logger.error "Failed to create transaction: #{e.message}"
          stats[:error] += 1
        end
      end

      parsing_session.complete!(stats)
      processed_file.mark_completed!

      # Create notifications for workspace members
      create_completion_notifications(parsing_session)

    rescue StandardError => e
      Rails.logger.error "Parsing failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      parsing_session.fail!
      processed_file.mark_failed!
    end
  end

  private

  def parse_file(processed_file)
    filename = processed_file.filename.downcase

    if filename.end_with?('.xls', '.xlsx')
      # Use Python parser for Excel files (more reliable)
      parse_with_python(processed_file)
    else
      # Use Ruby parser for other formats (PDF, CSV)
      parser = ParserRouter.route(processed_file)
      parser.parse
    end
  end

  def parse_with_python(processed_file)
    # Download file to temp location
    tempfile = download_to_tempfile(processed_file)

    begin
      result = PythonExcelParser.parse(tempfile.path)
      result[:transactions]
    ensure
      tempfile.close
      tempfile.unlink
    end
  end

  def download_to_tempfile(processed_file)
    blob_filename = processed_file.file.blob.filename.to_s
    extension = File.extname(blob_filename)
    basename = File.basename(blob_filename, extension)
    basename = 'statement' if basename.blank?

    tempfile = Tempfile.new([basename, extension])
    tempfile.binmode
    tempfile.write(processed_file.file.download)
    tempfile.rewind
    tempfile
  end

  def create_transaction(workspace, tx_data, parsing_session)
    category = match_category(workspace, tx_data[:merchant])
    institution = FinancialInstitution.find_by(identifier: tx_data[:institution_identifier])

    workspace.transactions.create!(
      date: tx_data[:date],
      merchant: tx_data[:merchant],
      description: tx_data[:description],
      amount: tx_data[:amount],
      category: category,
      financial_institution: institution,
      status: 'pending_review',
      parsing_session: parsing_session
    )
  end

  def match_category(workspace, merchant)
    return nil if merchant.blank?

    workspace.categories.find { |c| c.matches?(merchant) }
  end

  def find_duplicate(workspace, transaction)
    workspace.transactions
             .committed
             .where(date: transaction.date, merchant: transaction.merchant, amount: transaction.amount)
             .where.not(id: transaction.id)
             .first
  end

  def create_completion_notifications(parsing_session)
    workspace = parsing_session.workspace

    # Notify workspace owner
    if workspace.owner
      Notification.create_parsing_complete!(parsing_session, workspace.owner)
    end

    # Notify workspace members with write access
    workspace.workspace_memberships.where(role: %w[co_owner member_write]).find_each do |membership|
      next if membership.user_id == workspace.owner_id

      Notification.create_parsing_complete!(parsing_session, membership.user)
    end
  end
end
