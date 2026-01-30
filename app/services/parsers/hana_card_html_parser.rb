require "ferrum"

module Parsers
  class HanaCardHtmlParser < BaseParser
    class DecryptionError < StandardError; end
    class PasswordMissingError < StandardError; end
    class BrowserError < StandardError; end

    DECRYPT_WAIT_SECONDS = 3
    BROWSER_TIMEOUT = 30

    SKIP_MERCHANTS = %w[소계 합계 카드소계].freeze
    SKIP_MERCHANTS_SPACED = ["합 계", "이 용 금 액"].freeze

    def parse
      password = fetch_password
      tempfile = download_file
      transactions = []

      browser = nil
      begin
        browser = create_browser
        page = browser.create_page
        page.go_to("file://#{tempfile.path}")

        decrypt_content(page, password)

        raw_data = extract_transactions_via_js(page)
        if raw_data.nil?
          Rails.logger.error("[HanaCardHtmlParser] JS 추출 실패: #{processed_file.filename}")
          return transactions
        end

        period = raw_data["period"]
        unless period
          Rails.logger.warn("[HanaCardHtmlParser] 이용기간을 찾을 수 없습니다")
          return transactions
        end

        period_info = build_period_info(period)
        payment_date = if raw_data["payment_date"]
                         pd = raw_data["payment_date"]
                         Date.new(pd["year"], pd["month"], pd["day"])
                       else
                         period_info[:end_date]
                       end

        rows = raw_data["rows"] || []
        Rails.logger.info("[HanaCardHtmlParser] JS에서 #{rows.length}개 행 추출")

        rows.each do |row|
          tx = process_row(row, period_info, payment_date)
          transactions << tx if tx
        end

        Rails.logger.info("[HanaCardHtmlParser] 파싱 완료: #{transactions.length}건 추출")
      rescue Ferrum::Error => e
        Rails.logger.error("[HanaCardHtmlParser] Chrome 실행 오류: #{e.message}")
        raise BrowserError, "Headless Chrome 실행에 실패했습니다: #{e.message}"
      ensure
        browser&.quit
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

    def fetch_password
      user = processed_file.uploaded_by
      raise PasswordMissingError, "업로더 정보를 찾을 수 없습니다." if user.nil?

      pw = user.statement_password("hana_card")
      if pw.blank?
        raise PasswordMissingError, "하나카드 보안메일 비밀번호가 설정되지 않았습니다."
      end
      pw
    end

    def create_browser
      Ferrum::Browser.new(
        headless: true,
        timeout: BROWSER_TIMEOUT,
        browser_options: {
          "no-sandbox" => nil,
          "disable-gpu" => nil,
          "disable-dev-shm-usage" => nil
        }
      )
    rescue => e
      raise BrowserError, "Chrome 브라우저를 시작할 수 없습니다: #{e.message}"
    end

    def decrypt_content(page, password)
      page.at_css("#password")&.focus
      page.evaluate("document.getElementById('password').value = '#{escape_js(password)}'")
      page.evaluate("UserFunc()")

      sleep(DECRYPT_WAIT_SECONDS)

      title_changed = page.evaluate(<<~JS)
        (function() {
          return document.title.indexOf('하나카드 이용대금명세서') !== -1;
        })()
      JS

      unless title_changed
        raise DecryptionError, "보안메일 복호화에 실패했습니다. 비밀번호를 확인해주세요."
      end
    end

    # Extract structured transaction data directly from Chrome DOM via JavaScript.
    # Returns a hash with "period" and "rows" keys, or nil on failure.
    def extract_transactions_via_js(page)
      result = page.evaluate(<<~JS)
        (function() {
          var result = { period: null, payment_date: null, rows: [] };

          // Use textContent (not innerText) to include CSS-hidden elements
          var bodyText = document.body.textContent || '';
          var periodMatch = bodyText.match(/(\\d{4})\\.\\s*(\\d{1,2})\\.\\s*(\\d{1,2})\\s*~\\s*(\\d{4})\\.\\s*(\\d{1,2})\\.\\s*(\\d{1,2})/);
          if (periodMatch) {
            result.period = {
              start_year: parseInt(periodMatch[1]),
              start_month: parseInt(periodMatch[2]),
              start_day: parseInt(periodMatch[3]),
              end_year: parseInt(periodMatch[4]),
              end_month: parseInt(periodMatch[5]),
              end_day: parseInt(periodMatch[6])
            };
          }

          // Extract 원결제일 (e.g. "2026년 01월 23일")
          var payDateMatch = bodyText.match(/원결제일\\s*(\\d{4})\\s*년\\s*(\\d{1,2})\\s*월\\s*(\\d{1,2})\\s*일/);
          if (payDateMatch) {
            result.payment_date = {
              year: parseInt(payDateMatch[1]),
              month: parseInt(payDateMatch[2]),
              day: parseInt(payDateMatch[3])
            };
          }

          // Find the innermost transaction table by picking the table with
          // the most 11-cell rows that also contains "이용일자" header
          var allTables = document.querySelectorAll('table');
          var txTable = null;
          var maxElevenCellRows = 0;

          for (var t = 0; t < allTables.length; t++) {
            var tbl = allTables[t];
            var trs = tbl.rows;
            var hasHeader = false;
            var elevenCount = 0;

            for (var r = 0; r < trs.length; r++) {
              var cells = trs[r].cells;
              if (!hasHeader) {
                for (var c = 0; c < cells.length; c++) {
                  if (cells[c].textContent.trim() === '이용일자') {
                    hasHeader = true;
                    break;
                  }
                }
              }
              if (cells.length === 11) elevenCount++;
            }

            if (hasHeader && elevenCount > maxElevenCellRows) {
              maxElevenCellRows = elevenCount;
              txTable = tbl;
            }
          }

          if (!txTable) return result;

          // Iterate direct rows, skip until header, then extract 11-cell rows
          var trs = txTable.rows;
          var headerFound = false;

          for (var r = 0; r < trs.length; r++) {
            var cells = trs[r].cells;

            if (!headerFound) {
              for (var c = 0; c < cells.length; c++) {
                if (cells[c].textContent.trim() === '이용일자') {
                  headerFound = true;
                  break;
                }
              }
              continue;
            }

            // Transaction rows have exactly 11 cells
            if (cells.length !== 11) continue;

            var cellTexts = [];
            for (var c = 0; c < cells.length; c++) {
              cellTexts.push(cells[c].textContent.trim());
            }

            result.rows.push({
              date: cellTexts[0],
              merchant: cellTexts[1],
              usage_amount: cellTexts[2],
              installment_total: cellTexts[3],
              installment_month: cellTexts[4],
              payment_amount: cellTexts[5],
              fee: cellTexts[6],
              benefit_type: cellTexts[7],
              benefit_amount: cellTexts[8]
            });
          }

          return result;
        })()
      JS

      result
    rescue => e
      Rails.logger.error("[HanaCardHtmlParser] JS 평가 오류: #{e.message}")
      nil
    end

    def build_period_info(period)
      {
        start_year: period["start_year"],
        start_month: period["start_month"],
        end_year: period["end_year"],
        end_month: period["end_month"],
        end_date: Date.new(period["end_year"], period["end_month"], period["end_day"])
      }
    end

    def process_row(row, period_info, payment_date)
      date_text = row["date"].to_s.strip
      merchant = row["merchant"].to_s.strip

      # MM/DD format validation
      return nil unless date_text.match?(%r{\A\d{1,2}/\d{1,2}\z})

      # Skip summary rows
      return nil if skip_merchant?(merchant)

      # Resolve full date from MM/DD
      month, day = date_text.split("/").map(&:to_i)
      year = resolve_year(month, period_info)
      date = Date.new(year, month, day)

      # Installment info
      installment_total = parse_installment_field(row["installment_total"])
      installment_month = parse_installment_field(row["installment_month"])

      # Benefit info (이용혜택: 무이자, 할인, 온누리사용 등)
      benefit_type = row["benefit_type"].to_s.strip.presence
      benefit_amount_text = row["benefit_amount"].to_s.strip
      benefit_amount = benefit_amount_text.present? ? parse_amount(benefit_amount_text) : nil

      # Amount logic:
      # - 이용혜택이 있으면 → 결제금액(payment_amount) 사용 (할인 적용된 실제 결제액)
      # - 이용혜택이 없으면 → 이용금액(usage_amount) 사용 (취소 건 음수 보존)
      payment_amount_text = row["payment_amount"].to_s.strip
      usage_amount_text = row["usage_amount"].to_s.strip

      if benefit_type.present? && payment_amount_text.present?
        amount = parse_amount(payment_amount_text)
      else
        amount = parse_signed_amount(usage_amount_text)
      end
      return nil if amount.zero?

      # Determine payment_type from installment and benefit info
      is_installment = installment_total && installment_total > 1
      payment_type = if benefit_type == "온누리사용"
                       "coupon"
                     elsif is_installment
                       "installment"
                     else
                       "lump_sum"
                     end

      # For installment month 2+, use payment_date instead of transaction date
      use_payment_date = is_installment && installment_month && installment_month > 1 && payment_date
      final_date = use_payment_date ? payment_date : date

      build_transaction(
        date: final_date,
        merchant: merchant,
        amount: amount,
        description: merchant,
        installment_month: installment_month,
        installment_total: installment_total,
        payment_type: payment_type,
        benefit_type: benefit_type,
        benefit_amount: benefit_amount
      )
    rescue Date::Error => e
      Rails.logger.warn("[HanaCardHtmlParser] 날짜 파싱 실패: #{date_text} - #{e.message}")
      nil
    end

    def skip_merchant?(merchant)
      SKIP_MERCHANTS.any? { |term| merchant.include?(term) } ||
        SKIP_MERCHANTS_SPACED.any? { |term| merchant.include?(term) }
    end

    def parse_signed_amount(amount_string)
      return 0 if amount_string.blank?
      cleaned = amount_string.to_s.gsub(/[^\d.-]/, "")
      cleaned.to_i
    end

    def parse_installment_field(value)
      text = value.to_s.strip
      return nil unless text.present? && text.match?(/\d+/)
      text.to_i
    end

    def resolve_year(month, period_info)
      if month >= period_info[:start_month]
        period_info[:start_year]
      else
        period_info[:end_year]
      end
    end

    def escape_js(str)
      str.to_s
         .gsub("\\", "\\\\")
         .gsub("'", "\\'")
         .gsub("\n", "\\n")
         .gsub("\r", "\\r")
         .gsub("`", "\\`")
         .gsub("/", "\\/")
         .gsub("\u2028", "\\u2028")
         .gsub("\u2029", "\\u2029")
    end
  end
end
