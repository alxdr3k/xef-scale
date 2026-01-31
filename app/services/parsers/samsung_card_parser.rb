module Parsers
  class SamsungCardParser < BaseParser
    # 삼성카드 엑셀 명세서 파서
    # 시트: 일시불, 할부 (둘 다 파싱)
    # 컬럼: 이용일, 이용구분, 가맹점, 이용금액, 총할부금액, 이용혜택, 혜택금액, 개월, 회차, 원금, 이자/수수료, 포인트명, 적립금액, 입금후잔액

    HEADER_ROW = 3
    DATE_COL = 0        # 이용일 (YYYYMMDD)
    MERCHANT_COL = 2    # 가맹점
    AMOUNT_COL = 9      # 원금 (실제 청구 금액)
    MONTH_COL = 7       # 개월 (할부 개월 수)
    ROUND_COL = 8       # 회차 (현재 회차)

    def parse
      tempfile = download_file
      transactions = []

      begin
        xlsx = open_spreadsheet(tempfile)

        xlsx.sheets.each do |sheet_name|
          sheet = xlsx.sheet(sheet_name)
          sheet_transactions = parse_sheet(sheet, sheet_name)
          transactions.concat(sheet_transactions)
        end
      ensure
        tempfile.close
        tempfile.unlink
      end

      transactions
    end

    protected

    def institution_identifier
      "samsung_card"
    end

    private

    def parse_sheet(sheet, sheet_name)
      transactions = []
      payment_type = determine_payment_type(sheet_name)

      ((HEADER_ROW + 1)..sheet.last_row).each do |row_num|
        row = sheet.row(row_num)
        next if row.compact.empty?

        tx = parse_row(row, payment_type)
        transactions << tx if tx
      end

      transactions
    end

    def determine_payment_type(sheet_name)
      case sheet_name
      when /할부/
        "installment"
      else
        "one_time"
      end
    end

    def parse_row(row, payment_type)
      date_str = row[DATE_COL].to_s.strip
      return nil if date_str.blank?
      return nil if date_str.include?("합계")

      date = parse_samsung_date(date_str)
      return nil unless date

      merchant = row[MERCHANT_COL].to_s.strip
      return nil if merchant.blank? || merchant.include?("합계")

      # 원금 컬럼 사용 (실제 이번 달 청구 금액)
      amount = extract_amount(row[AMOUNT_COL])
      return nil if amount.zero?

      # 할부 정보
      installment_total = nil
      installment_month = nil

      if payment_type == "installment"
        installment_total = row[MONTH_COL].to_i if row[MONTH_COL].present?
        installment_month = row[ROUND_COL].to_i if row[ROUND_COL].present?
      end

      build_transaction(
        date: date,
        merchant: merchant,
        amount: amount,
        payment_type: payment_type,
        installment_month: installment_month,
        installment_total: installment_total
      )
    end

    def parse_samsung_date(date_str)
      return nil if date_str.blank?

      # 삼성카드 날짜 형식: YYYYMMDD (예: 20250927)
      if date_str =~ /\A(\d{4})(\d{2})(\d{2})\z/
        year, month, day = $1.to_i, $2.to_i, $3.to_i
        return Date.new(year, month, day)
      end

      # 다른 형식 시도
      parse_date(date_str)
    rescue ArgumentError
      nil
    end

    def extract_amount(value)
      return 0 if value.blank?

      if value.is_a?(Numeric)
        value.to_i
      else
        parse_amount(value)
      end
    end
  end
end
