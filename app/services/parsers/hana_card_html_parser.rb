module Parsers
  class HanaCardHtmlParser < BaseParser
    class DecryptionError < StandardError; end
    class PasswordMissingError < StandardError; end
    class BrowserError < StandardError; end

    # Ferrum 대기 시간 설정
    DECRYPT_WAIT_SECONDS = 3
    BROWSER_TIMEOUT = 30

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
        decrypted_html = extract_decrypted_html(page)

        if decrypted_html.blank?
          Rails.logger.error("[HanaCardHtmlParser] 복호화된 콘텐츠가 비어 있습니다: #{processed_file.filename}")
          return transactions
        end

        dump_html_for_debug(decrypted_html)
        transactions = parse_transactions(decrypted_html)
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
      # #password input에 비밀번호 입력
      page.at_css("#password")&.focus
      page.evaluate("document.getElementById('password').value = '#{escape_js(password)}'")

      # UserFunc() 실행하여 복호화
      page.evaluate("UserFunc()")

      # 복호화 완료 대기
      sleep(DECRYPT_WAIT_SECONDS)

      # 복호화 성공 여부 확인: #uni_cont_body에 콘텐츠가 있는지 체크
      content_present = page.evaluate(<<~JS)
        (function() {
          var el = document.getElementById('uni_cont_body');
          return el && el.innerHTML.trim().length > 0;
        })()
      JS

      unless content_present
        raise DecryptionError, "보안메일 복호화에 실패했습니다. 비밀번호를 확인해주세요."
      end
    end

    def extract_decrypted_html(page)
      page.evaluate(<<~JS)
        (function() {
          var el = document.getElementById('uni_cont_body');
          return el ? el.innerHTML : '';
        })()
      JS
    end

    def dump_html_for_debug(html)
      Rails.logger.info("[HanaCardHtmlParser] 복호화된 HTML 길이: #{html.length} bytes")
    end

    def parse_transactions(html)
      doc = Nokogiri::HTML::DocumentFragment.parse(html)
      transactions = []

      # 전략: 거래 데이터가 포함된 테이블을 찾는다
      # 하나카드 명세서는 일반적으로 "거래일자", "가맹점명", "이용금액" 등의 헤더를 가진
      # 테이블에 거래 내역이 포함된다
      tables = doc.css("table")

      if tables.empty?
        Rails.logger.warn("[HanaCardHtmlParser] 복호화된 HTML에서 테이블을 찾을 수 없습니다")
        return transactions
      end

      target_table = find_transaction_table(tables)
      unless target_table
        Rails.logger.warn("[HanaCardHtmlParser] 거래 내역 테이블을 식별할 수 없습니다. 첫 번째 테이블을 시도합니다.")
        target_table = tables.first
      end

      header_map = detect_header_columns(target_table)
      rows = target_table.css("tr")

      rows.each do |row|
        cells = row.css("td")
        next if cells.empty?
        next if cells.length < 3 # 최소 날짜, 가맹점, 금액

        tx = parse_table_row(cells, header_map)
        transactions << tx if tx
      end

      Rails.logger.info("[HanaCardHtmlParser] 파싱 완료: #{transactions.length}건 추출")
      transactions
    end

    def find_transaction_table(tables)
      keywords = %w[거래일 이용일 가맹점 이용금액 결제금액 청구금액]

      tables.find do |table|
        header_text = table.css("th, thead td, tr:first-child td").text
        keywords.count { |kw| header_text.include?(kw) } >= 2
      end
    end

    def detect_header_columns(table)
      # 기본 컬럼 매핑 (하나카드 Excel 명세서 구조 기반 추정)
      header_map = { date: 0, merchant: 1, amount: 2, installment_total: nil, installment_month: nil }

      header_row = table.at_css("thead tr, tr:first-child")
      return header_map unless header_row

      cells = header_row.css("th, td")
      cells.each_with_index do |cell, idx|
        text = cell.text.strip
        case text
        when /거래일|이용일/
          header_map[:date] = idx
        when /가맹점|이용처|상호/
          header_map[:merchant] = idx
        when /이용금액|결제금액|청구금액|금액/
          header_map[:amount] = idx
        when /할부기간|할부/
          header_map[:installment_total] = idx
        when /청구회차|회차/
          header_map[:installment_month] = idx
        end
      end

      header_map
    end

    def parse_table_row(cells, header_map)
      date_text = cell_text(cells, header_map[:date])
      return nil if date_text.blank?

      date = parse_date(date_text)
      return nil unless date

      merchant = cell_text(cells, header_map[:merchant])
      return nil if merchant.blank?

      amount_text = cell_text(cells, header_map[:amount])
      amount = parse_amount(amount_text)
      return nil if amount.zero?

      installment_total = nil
      installment_month = nil

      if !header_map[:installment_total].nil? && header_map[:installment_total] < cells.length
        raw_total = cell_text(cells, header_map[:installment_total])
        installment_total = raw_total.to_i if raw_total.present? && raw_total != "-"
      end

      if !header_map[:installment_month].nil? && header_map[:installment_month] < cells.length
        raw_month = cell_text(cells, header_map[:installment_month])
        installment_month = raw_month.to_i if raw_month.present? && raw_month != "-"
      end

      build_transaction(
        date: date,
        merchant: merchant,
        amount: amount,
        description: merchant,
        installment_month: installment_month,
        installment_total: installment_total
      )
    end

    def cell_text(cells, index)
      return "" if index.nil? || index >= cells.length
      cells[index].text.strip
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
