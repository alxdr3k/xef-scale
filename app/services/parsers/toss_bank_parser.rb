module Parsers
  class TossBankParser < BaseParser
    def parse
      tempfile = download_file
      transactions = []

      begin
        filename = processed_file.filename.downcase

        if filename.end_with?('.xlsx', '.xls')
          transactions = parse_excel(tempfile)
        elsif filename.end_with?('.csv')
          transactions = parse_csv(tempfile)
        end
      ensure
        tempfile.close
        tempfile.unlink
      end

      transactions
    end

    protected

    def institution_identifier
      'toss_bank'
    end

    private

    def parse_excel(tempfile)
      transactions = []
      xlsx = open_spreadsheet(tempfile)
      sheet = xlsx.sheet(0)

      # Toss usually has metadata in first few rows
      data_start_row = find_data_start_row(sheet)
      headers = identify_columns(sheet.row(data_start_row - 1))

      (data_start_row..sheet.last_row).each do |row_num|
        row = sheet.row(row_num)
        next if row.compact.empty?

        tx = parse_row_with_headers(row, headers)
        transactions << tx if tx
      end

      transactions
    end

    def parse_csv(tempfile)
      transactions = []
      require 'csv'

      csv = CSV.read(tempfile.path, encoding: 'UTF-8')

      data_start_row = find_data_start_row_csv(csv)
      headers = identify_columns(csv[data_start_row - 1])

      csv[data_start_row..-1].each do |row|
        next if row.compact.empty?

        tx = parse_row_with_headers(row, headers)
        transactions << tx if tx
      end

      transactions
    end

    def find_data_start_row(sheet)
      (1..15).each do |row_num|
        row = sheet.row(row_num)
        content = row.compact.map(&:to_s).join(' ')

        if content.include?('거래일') || content.include?('일시') || content.include?('날짜')
          return row_num + 1
        end
      end
      4
    end

    def find_data_start_row_csv(csv)
      csv.each_with_index do |row, idx|
        content = row.compact.map(&:to_s).join(' ')
        if content.include?('거래일') || content.include?('일시') || content.include?('날짜')
          return idx + 1
        end
      end
      3
    end

    def identify_columns(header_row)
      headers = {}
      header_row.each_with_index do |cell, idx|
        next unless cell

        str = cell.to_s.downcase
        headers[:date] = idx if str.include?('일') && (str.include?('거래') || str.include?('날짜'))
        headers[:merchant] = idx if str.include?('내용') || str.include?('기재') || str.include?('적요')
        headers[:outgoing] = idx if str.include?('출금') || str.include?('보낸')
        headers[:incoming] = idx if str.include?('입금') || str.include?('받은')
        headers[:amount] = idx if str.include?('금액') && !str.include?('입') && !str.include?('출')
      end
      headers
    end

    def parse_row_with_headers(row, headers)
      date_col = headers[:date] || 0
      merchant_col = headers[:merchant] || 1
      outgoing_col = headers[:outgoing]
      incoming_col = headers[:incoming]
      amount_col = headers[:amount]

      date = parse_date(row[date_col])
      return nil unless date

      merchant = row[merchant_col].to_s.strip
      return nil if merchant.blank?

      # Determine amount (prefer outgoing for expenses)
      amount = if outgoing_col && row[outgoing_col].present?
                 parse_amount(row[outgoing_col])
               elsif amount_col && row[amount_col].present?
                 parse_amount(row[amount_col])
               elsif incoming_col && row[incoming_col].present?
                 # This is income, might want to skip or handle differently
                 parse_amount(row[incoming_col])
               else
                 0
               end

      return nil if amount.zero?

      build_transaction(date: date, merchant: merchant, amount: amount)
    end
  end
end
