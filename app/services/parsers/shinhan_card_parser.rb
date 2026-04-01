module Parsers
  class ShinhanCardParser < BaseParser
    IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .webp .heic].freeze

    MIME_TYPES = {
      ".jpg" => "image/jpeg",
      ".jpeg" => "image/jpeg",
      ".png" => "image/png",
      ".webp" => "image/webp",
      ".heic" => "image/heic"
    }.freeze

    def parse
      tempfile = download_file
      transactions = []

      begin
        filename = processed_file.filename.downcase
        ext = File.extname(filename)

        if IMAGE_EXTENSIONS.include?(ext)
          transactions = parse_image(tempfile, ext)
        elsif filename.end_with?(".pdf")
          transactions = parse_pdf(tempfile)
        elsif filename.end_with?(".xlsx", ".xls")
          transactions = parse_excel(tempfile)
        end
      ensure
        tempfile.close
        tempfile.unlink
      end

      transactions
    end

    protected

    def institution_identifier
      "shinhan_card"
    end

    private

    def parse_image(tempfile, ext)
      mime_type = MIME_TYPES[ext] || "image/jpeg"
      service = GeminiVisionParserService.new
      raw_transactions = service.parse_image(tempfile, mime_type: mime_type)

      raw_transactions.map do |tx|
        date = parse_date(tx[:date])
        next unless date

        build_transaction(
          date: date,
          merchant: tx[:merchant],
          amount: tx[:amount],
          payment_type: tx[:payment_type],
          installment_month: tx[:installment_month],
          installment_total: tx[:installment_total]
        )
      end.compact
    end

    def parse_excel(tempfile)
      transactions = []
      xlsx = open_spreadsheet(tempfile)
      sheet = xlsx.sheet(0)

      data_start_row = find_data_start_row(sheet)

      (data_start_row..sheet.last_row).each do |row_num|
        row = sheet.row(row_num)
        next if row.compact.empty?

        tx = parse_excel_row(row)
        transactions << tx if tx
      end

      transactions
    end

    def find_data_start_row(sheet)
      (1..20).each do |row_num|
        row = sheet.row(row_num)
        content = row.compact.map(&:to_s).join(" ")

        if content.include?("이용일") || content.include?("가맹점") || content.include?("승인")
          return row_num + 1
        end
      end
      5
    end

    def parse_excel_row(row)
      date_str = row[0].to_s.strip
      date = parse_date(date_str)
      return nil unless date

      merchant = row[2].to_s.strip  # Usually 3rd column
      merchant = row[1].to_s.strip if merchant.blank?

      amount = parse_amount(row[3]) || parse_amount(row[4])
      return nil if amount.zero?

      build_transaction(date: date, merchant: merchant, amount: amount)
    end

    def parse_pdf(tempfile)
      Rails.logger.warn "Shinhan Card PDF parsing is not supported: #{processed_file.filename}"
      []
    end
  end
end
