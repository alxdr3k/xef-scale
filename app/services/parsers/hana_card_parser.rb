module Parsers
  class HanaCardParser < BaseParser
    def parse
      tempfile = download_file
      transactions = []

      begin
        xlsx = open_spreadsheet(tempfile)
        sheet = xlsx.sheet(0)

        # Find the header row with "거래일자"
        header_row = find_header_row(sheet)
        return transactions unless header_row

        # Parse transactions starting after header row
        # Skip rows that contain card info (e.g., "하나카드 본인")
        ((header_row + 1)..sheet.last_row).each do |row_num|
          row = sheet.row(row_num)
          next if row.compact.empty?

          # Skip card info rows
          first_cell = row[0].to_s
          next if first_cell.include?('하나카드') || first_cell.include?('본인')

          tx = parse_transaction_row(row)
          transactions << tx if tx
        end
      ensure
        tempfile.close
        tempfile.unlink
      end

      transactions
    end

    protected

    def institution_identifier
      'hana_card'
    end

    private

    def find_header_row(sheet)
      (1..40).each do |row_num|
        row = sheet.row(row_num)
        first_cell = row[0].to_s.strip

        # Look for header row with "거래일자"
        return row_num if first_cell == '거래일자'
      end
      nil
    end

    def parse_transaction_row(row)
      # Format: [date, merchant, amount, installment, ...]
      # Column 0: Date (YYYY.MM.DD)
      # Column 1: Merchant name
      # Column 2: Amount

      date_str = row[0].to_s.strip
      return nil unless date_str.match?(/^\d{4}\.\d{2}\.\d{2}$/)

      date = parse_date(date_str)
      return nil unless date

      merchant = row[1].to_s.strip
      return nil if merchant.blank?

      # Amount is in column 2 (이용금액)
      amount = row[2].to_i
      return nil if amount <= 0

      build_transaction(
        date: date,
        merchant: merchant,
        amount: amount,
        description: merchant
      )
    end
  end
end
