module Parsers
  class HanaCardParser < BaseParser
    def parse
      tempfile = download_file
      transactions = []

      begin
        xlsx = open_spreadsheet(tempfile)
        sheet = xlsx.sheet(0)

        # 출금일 파싱 (Row 5, Column 6: "2025.10.23")
        payment_date = parse_payment_date(sheet)

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
          next if first_cell.include?("하나카드") || first_cell.include?("본인")

          tx = parse_transaction_row(row, payment_date)
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
      "hana_card"
    end

    private

    def find_header_row(sheet)
      (1..40).each do |row_num|
        row = sheet.row(row_num)
        first_cell = row[0].to_s.strip

        # Look for header row with "거래일자"
        return row_num if first_cell == "거래일자"
      end
      nil
    end

    def parse_payment_date(sheet)
      # Row 5, Column 6 contains payment date (출금일: "2025.10.23")
      date_str = sheet.row(5)[6].to_s.strip
      parse_date(date_str)
    end

    def parse_transaction_row(row, payment_date = nil)
      # Column 0: Date (YYYY.MM.DD) - 거래일자
      # Column 1: Merchant name - 가맹점명
      # Column 2: Amount - 이용금액 (총액)
      # Column 3: Installment total - 할부기간 (e.g., 5.0 or "-")
      # Column 4: Installment month - 청구회차 (e.g., 1.0 or "-")
      # Column 5: Payment amount - 결제원금 (회차당 금액)

      date_str = row[0].to_s.strip
      return nil unless date_str.match?(/^\d{4}\.\d{2}\.\d{2}$/)

      date = parse_date(date_str)
      return nil unless date

      merchant = row[1].to_s.strip
      return nil if merchant.blank?

      # Parse installment info first
      installment_total_raw = row[3].to_s.strip
      installment_month_raw = row[4].to_s.strip

      installment_total = nil
      installment_month = nil

      if installment_total_raw != "-" && installment_total_raw.present?
        installment_total = installment_total_raw.to_i
        installment_month = installment_month_raw.to_i if installment_month_raw != "-"
      end

      # 할부 거래는 결제원금(column 5), 일시불은 이용금액(column 2) 사용
      is_installment = installment_total && installment_total > 1
      amount = is_installment ? row[5].to_i : row[2].to_i
      return nil if amount.zero?

      # 할부 2회차 이후는 출금일 사용, 1회차와 일시불은 원래 거래일 사용
      use_payment_date = is_installment && installment_month && installment_month > 1 && payment_date
      final_date = use_payment_date ? payment_date : date

      build_transaction(
        date: final_date,
        merchant: merchant,
        amount: amount,
        description: merchant,
        installment_month: installment_month,
        installment_total: installment_total
      )
    end
  end
end
