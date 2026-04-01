module Parsers
  class MgBankParser < BaseParser
    def parse
      tempfile = download_file
      transactions = []

      begin
        reader = PDF::Reader.new(tempfile.path)

        reader.pages.each do |page|
          page_transactions = parse_page(page.text)
          transactions.concat(page_transactions)
        end
      ensure
        tempfile.close
        tempfile.unlink
      end

      transactions
    end

    protected

    def institution_identifier
      "mg_bank"
    end

    private

    # date time type merchant outgoing incoming balance
    TRANSACTION_PATTERN = /(\d{4}\.\d{2}\.\d{2})\s+\d{2}:\d{2}:\d{2}\s+\S+\s+(.+?)\s+([\d,]+)\s*원\s+([\d,]+)\s*원\s+[\d,]+\s*원/

    def parse_page(text)
      transactions = []

      text.each_line do |line|
        line = line.strip
        next if line.empty?

        match = line.match(TRANSACTION_PATTERN)
        next unless match

        date = parse_date(match[1])
        next unless date

        merchant = match[2].strip
        next if merchant.blank?

        outgoing = match[3].gsub(",", "").to_i
        incoming = match[4].gsub(",", "").to_i

        # 지출(출금)만 파싱, 입금 건은 스킵
        next if outgoing.zero?
        next if incoming > 0 && outgoing.zero?

        transactions << build_transaction(date: date, merchant: merchant, amount: outgoing)
      end

      transactions
    end
  end
end
