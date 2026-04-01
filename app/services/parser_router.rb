class ParserRouter
  class UnknownFormatError < StandardError; end

  SIGNATURES = {
    hana_card_html: [ "USSM_M_DATA", "UniSafeMail", "uni_cont_body" ],
    mg_bank: [ "출금가능금액", "거래내용/메모", "온라인자립예탁금" ],
    toss_bank: [ "토스뱅크", "Toss", "수신자", "거래유형" ],
    kakao_bank: [ "kakao", "카카오뱅크", "거래일시", "거래구분" ],
    shinhan_card: [ "신한카드", "이용일자", "승인번호" ],
    hana_card: [ "하나카드", "가맹점명", "이용대금 명세서", "거래일자" ],
    samsung_card: [ "삼성카드", "입금후잔액", "이용구분" ]
  }.freeze

  PARSERS = {
    "shinhan_card" => Parsers::ShinhanCardParser,
    "hana_card" => Parsers::HanaCardParser,
    "hana_card_html" => Parsers::HanaCardHtmlParser,
    "toss_bank" => Parsers::TossBankParser,
    "kakao_bank" => Parsers::KakaoBankParser,
    "samsung_card" => Parsers::SamsungCardParser,
    "mg_bank" => Parsers::MgBankParser
  }.freeze

  def self.route_by_identifier(identifier, processed_file)
    klass = PARSERS[identifier]
    raise UnknownFormatError, "지원하지 않는 금융기관입니다: #{identifier}" unless klass
    klass.new(processed_file)
  end

  def self.route(processed_file)
    # HTML 파일은 확장자로 직접 라우팅 (시그니처가 파일 후반부에 위치할 수 있음)
    filename = processed_file.filename.downcase
    if filename.end_with?(".html", ".htm")
      return Parsers::HanaCardHtmlParser.new(processed_file)
    end

    content = read_file_content(processed_file)
    institution = identify_institution(content)

    case institution
    when :hana_card_html
      Parsers::HanaCardHtmlParser.new(processed_file)
    when :toss_bank
      Parsers::TossBankParser.new(processed_file)
    when :kakao_bank
      Parsers::KakaoBankParser.new(processed_file)
    when :shinhan_card
      Parsers::ShinhanCardParser.new(processed_file)
    when :hana_card
      Parsers::HanaCardParser.new(processed_file)
    when :samsung_card
      Parsers::SamsungCardParser.new(processed_file)
    when :mg_bank
      Parsers::MgBankParser.new(processed_file)
    else
      raise UnknownFormatError, "지원하지 않는 명세서 형식입니다."
    end
  end

  def self.read_file_content(processed_file)
    return "" unless processed_file.file.attached?

    filename = processed_file.filename.downcase

    if filename.end_with?(".xlsx", ".xls")
      read_excel_content(processed_file)
    elsif filename.end_with?(".csv")
      read_csv_content(processed_file)
    elsif filename.end_with?(".pdf")
      read_pdf_content(processed_file)
    elsif filename.end_with?(".html", ".htm")
      read_html_content(processed_file)
    else
      ""
    end
  end

  def self.read_excel_content(processed_file)
    tempfile = download_to_tempfile(processed_file)

    # Determine extension from content_type
    content_type = processed_file.file.blob.content_type
    extension = case content_type
    when "application/vnd.ms-excel" then :xls
    when "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" then :xlsx
    else :xls
    end

    xlsx = Roo::Spreadsheet.open(tempfile.path, extension: extension)
    sheet = xlsx.sheet(0)

    # Read first 10 rows for identification
    content = []
    (1..[ 10, sheet.last_row ].min).each do |row|
      content << sheet.row(row).compact.join(" ")
    end

    tempfile.close
    tempfile.unlink

    content.join("\n")
  end

  def self.read_csv_content(processed_file)
    tempfile = download_to_tempfile(processed_file)
    content = File.read(tempfile.path, encoding: "UTF-8")
    tempfile.close
    tempfile.unlink
    content[0..2000]  # First 2000 chars
  end

  def self.read_pdf_content(processed_file)
    tempfile = download_to_tempfile(processed_file)
    begin
      reader = PDF::Reader.new(tempfile.path)
      content = reader.pages.first(3).map(&:text).join("\n")
      content[0..2000]
    rescue PDF::Reader::EncryptedPDFError
      # Encrypted PDF - assume Shinhan Card for now
      "신한카드 encrypted_pdf"
    rescue PDF::Reader::MalformedPDFError
      # Malformed or protected PDF
      "신한카드 encrypted_pdf"
    ensure
      tempfile.close
      tempfile.unlink
    end
  end

  def self.read_html_content(processed_file)
    tempfile = download_to_tempfile(processed_file)
    begin
      content = File.read(tempfile.path, encoding: "UTF-8")
      content[0..5000]  # First 5000 chars for signature detection
    ensure
      tempfile.close
      tempfile.unlink
    end
  end

  def self.download_to_tempfile(processed_file)
    # Use ActiveStorage attachment's filename
    blob_filename = processed_file.file.blob.filename.to_s
    extension = File.extname(blob_filename)
    basename = File.basename(blob_filename, extension)
    # Ensure basename is not empty
    basename = "statement" if basename.blank?
    tempfile = Tempfile.new([ basename, extension ])
    tempfile.binmode
    tempfile.write(processed_file.file.download)
    tempfile.rewind
    tempfile
  end

  def self.identify_institution(content)
    SIGNATURES.each do |institution, keywords|
      return institution if keywords.any? { |kw| content.include?(kw) }
    end
    nil
  end
end
