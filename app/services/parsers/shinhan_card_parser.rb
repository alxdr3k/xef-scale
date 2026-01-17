module Parsers
  class ShinhanCardParser < BaseParser
    def parse
      tempfile = download_file
      transactions = []

      begin
        filename = processed_file.filename.downcase

        if filename.end_with?('.pdf')
          transactions = parse_pdf(tempfile)
        elsif filename.end_with?('.xlsx', '.xls')
          transactions = parse_excel(tempfile)
        else
          transactions = parse_text(tempfile)
        end
      ensure
        tempfile.close
        tempfile.unlink
      end

      transactions
    end

    protected

    def institution_identifier
      'shinhan_card'
    end

    private

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
        content = row.compact.map(&:to_s).join(' ')

        if content.include?('이용일') || content.include?('가맹점') || content.include?('승인')
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
      transactions = []
      reader = PDF::Reader.new(tempfile.path)

      text = reader.pages.map(&:text).join("\n")
      transactions = extract_transactions_from_text(text)

      transactions
    end

    def parse_text(tempfile)
      text = File.read(tempfile.path, encoding: 'UTF-8')
      extract_transactions_from_text(text)
    end

    def extract_transactions_from_text(text)
      transactions = []
      lines = text.split("\n").map(&:strip)

      current_date = nil
      current_merchant = nil

      lines.each_with_index do |line, i|
        # Look for date pattern (YY.MM.DD or YYYY.MM.DD)
        if line.match?(/^\d{2}\.\d{2}\.\d{2}$/)
          yy, mm, dd = line.split('.')
          current_date = Date.new(2000 + yy.to_i, mm.to_i, dd.to_i)

          # Next line might be merchant
          next_line = lines[i + 1].to_s.strip
          next_line = next_line.sub(/^본인\d+\s*/, '')  # Remove prefix like "본인357"
          current_merchant = next_line if next_line.present? && !next_line.match?(/^[\d,]+$/)

        elsif line.match?(/^[\d,]+$/) && current_date && current_merchant
          amount = line.gsub(',', '').to_i

          if amount >= 100
            transactions << build_transaction(
              date: current_date,
              merchant: current_merchant,
              amount: amount
            )
          end

          current_date = nil
          current_merchant = nil
        end
      end

      transactions
    end
  end
end
