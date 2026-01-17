class ParserRouter
  class UnknownFormatError < StandardError; end

  SIGNATURES = {
    toss_bank: ['토스뱅크', 'Toss', '수신자', '거래유형'],
    kakao_bank: ['kakao', '카카오뱅크', '거래일시', '거래구분'],
    shinhan_card: ['신한카드', '이용일자', '승인번호'],
    hana_card: ['하나카드', '이용일', '가맹점명', '이용대금 명세서', '거래일자']
  }.freeze

  def self.route(processed_file)
    content = read_file_content(processed_file)
    institution = identify_institution(content)

    case institution
    when :toss_bank
      Parsers::TossBankParser.new(processed_file)
    when :kakao_bank
      Parsers::KakaoBankParser.new(processed_file)
    when :shinhan_card
      Parsers::ShinhanCardParser.new(processed_file)
    when :hana_card
      Parsers::HanaCardParser.new(processed_file)
    else
      raise UnknownFormatError, "지원하지 않는 명세서 형식입니다."
    end
  end

  def self.read_file_content(processed_file)
    return '' unless processed_file.file.attached?

    filename = processed_file.filename.downcase

    if filename.end_with?('.xlsx', '.xls')
      read_excel_content(processed_file)
    elsif filename.end_with?('.csv')
      read_csv_content(processed_file)
    elsif filename.end_with?('.pdf')
      read_pdf_content(processed_file)
    else
      ''
    end
  end

  def self.read_excel_content(processed_file)
    tempfile = download_to_tempfile(processed_file)

    # Determine extension from content_type
    content_type = processed_file.file.blob.content_type
    extension = case content_type
                when 'application/vnd.ms-excel' then :xls
                when 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' then :xlsx
                else :xls
                end

    xlsx = Roo::Spreadsheet.open(tempfile.path, extension: extension)
    sheet = xlsx.sheet(0)

    # Read first 10 rows for identification
    content = []
    (1..[10, sheet.last_row].min).each do |row|
      content << sheet.row(row).compact.join(' ')
    end

    tempfile.close
    tempfile.unlink

    content.join("\n")
  end

  def self.read_csv_content(processed_file)
    tempfile = download_to_tempfile(processed_file)
    content = File.read(tempfile.path, encoding: 'UTF-8')
    tempfile.close
    tempfile.unlink
    content[0..2000]  # First 2000 chars
  end

  def self.read_pdf_content(processed_file)
    tempfile = download_to_tempfile(processed_file)
    reader = PDF::Reader.new(tempfile.path)

    content = reader.pages.first(3).map(&:text).join("\n")
    tempfile.close
    tempfile.unlink
    content[0..2000]
  end

  def self.download_to_tempfile(processed_file)
    # Use ActiveStorage attachment's filename
    blob_filename = processed_file.file.blob.filename.to_s
    extension = File.extname(blob_filename)
    basename = File.basename(blob_filename, extension)
    # Ensure basename is not empty
    basename = 'statement' if basename.blank?
    tempfile = Tempfile.new([basename, extension])
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
