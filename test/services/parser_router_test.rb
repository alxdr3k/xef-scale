require "test_helper"

class ParserRouterTest < ActiveSupport::TestCase
  test "identify_institution returns toss_bank for toss content" do
    content = "토스뱅크 거래내역서 수신자 홍길동"
    result = ParserRouter.identify_institution(content)
    assert_equal :toss_bank, result
  end

  test "identify_institution returns kakao_bank for kakao content" do
    content = "카카오뱅크 거래일시 2024.01.15"
    result = ParserRouter.identify_institution(content)
    assert_equal :kakao_bank, result
  end

  test "identify_institution returns shinhan_card for shinhan content" do
    content = "신한카드 이용일자 승인번호"
    result = ParserRouter.identify_institution(content)
    assert_equal :shinhan_card, result
  end

  test "identify_institution returns hana_card for hana content" do
    content = "하나카드 이용일 가맹점명"
    result = ParserRouter.identify_institution(content)
    assert_equal :hana_card, result
  end

  test "identify_institution returns nil for unknown content" do
    content = "Unknown bank statement format"
    result = ParserRouter.identify_institution(content)
    assert_nil result
  end

  test "SIGNATURES contains expected institutions" do
    assert_includes ParserRouter::SIGNATURES.keys, :toss_bank
    assert_includes ParserRouter::SIGNATURES.keys, :kakao_bank
    assert_includes ParserRouter::SIGNATURES.keys, :shinhan_card
    assert_includes ParserRouter::SIGNATURES.keys, :hana_card
  end

  test "read_file_content returns empty for no attachment" do
    pf = ProcessedFile.new(filename: 'test.csv', status: 'pending')
    result = ParserRouter.read_file_content(pf)
    assert_equal '', result
  end

  test "read_file_content returns empty for unknown extension" do
    pf = ProcessedFile.new(filename: 'test.doc', status: 'pending')
    result = ParserRouter.read_file_content(pf)
    assert_equal '', result
  end

  test "UnknownFormatError is defined" do
    assert ParserRouter::UnknownFormatError < StandardError
  end

  test "route raises UnknownFormatError for unknown content" do
    processed_file = ProcessedFile.new(filename: 'test.txt', status: 'pending')
    # No attachment, so content will be empty
    assert_raises(ParserRouter::UnknownFormatError) do
      ParserRouter.route(processed_file)
    end
  end

  test "route returns TossBankParser for toss content" do
    processed_file = processed_files(:pending_file)
    # Attach a CSV file with toss content
    csv_content = "토스뱅크,거래일시,거래유형\n2024-01-15,출금,10000"
    file = Tempfile.new(['toss', '.csv'])
    file.write(csv_content)
    file.rewind

    processed_file.file.attach(
      io: File.open(file.path),
      filename: 'toss.csv',
      content_type: 'text/csv'
    )
    processed_file.update!(filename: 'toss.csv')

    parser = ParserRouter.route(processed_file)
    assert_instance_of Parsers::TossBankParser, parser

    file.close
    file.unlink
  end

  test "route returns KakaoBankParser for kakao content" do
    processed_file = processed_files(:pending_file)
    csv_content = "카카오뱅크,거래일시,거래구분\n2024-01-15,출금,10000"
    file = Tempfile.new(['kakao', '.csv'])
    file.write(csv_content)
    file.rewind

    processed_file.file.attach(
      io: File.open(file.path),
      filename: 'kakao.csv',
      content_type: 'text/csv'
    )
    processed_file.update!(filename: 'kakao.csv')

    parser = ParserRouter.route(processed_file)
    assert_instance_of Parsers::KakaoBankParser, parser

    file.close
    file.unlink
  end

  test "route returns ShinhanCardParser for shinhan content" do
    processed_file = processed_files(:pending_file)
    csv_content = "신한카드,이용일자,승인번호\n2024-01-15,1234,10000"
    file = Tempfile.new(['shinhan', '.csv'])
    file.write(csv_content)
    file.rewind

    processed_file.file.attach(
      io: File.open(file.path),
      filename: 'shinhan.csv',
      content_type: 'text/csv'
    )
    processed_file.update!(filename: 'shinhan.csv')

    parser = ParserRouter.route(processed_file)
    assert_instance_of Parsers::ShinhanCardParser, parser

    file.close
    file.unlink
  end

  test "route returns HanaCardParser for hana content" do
    processed_file = processed_files(:pending_file)
    csv_content = "하나카드,이용일,가맹점명\n2024-01-15,테스트,10000"
    file = Tempfile.new(['hana', '.csv'])
    file.write(csv_content)
    file.rewind

    processed_file.file.attach(
      io: File.open(file.path),
      filename: 'hana.csv',
      content_type: 'text/csv'
    )
    processed_file.update!(filename: 'hana.csv')

    parser = ParserRouter.route(processed_file)
    assert_instance_of Parsers::HanaCardParser, parser

    file.close
    file.unlink
  end

  test "read_csv_content reads csv file content" do
    processed_file = processed_files(:pending_file)
    csv_content = "header1,header2,header3\nvalue1,value2,value3"
    file = Tempfile.new(['test', '.csv'])
    file.write(csv_content)
    file.rewind

    processed_file.file.attach(
      io: File.open(file.path),
      filename: 'test.csv',
      content_type: 'text/csv'
    )
    processed_file.update!(filename: 'test.csv')

    result = ParserRouter.read_file_content(processed_file)
    assert_includes result, 'header1'
    assert_includes result, 'value1'

    file.close
    file.unlink
  end

  test "download_to_tempfile creates tempfile with content" do
    processed_file = processed_files(:pending_file)
    csv_content = "test content"
    file = Tempfile.new(['test', '.csv'])
    file.write(csv_content)
    file.rewind

    processed_file.file.attach(
      io: File.open(file.path),
      filename: 'test.csv',
      content_type: 'text/csv'
    )

    tempfile = ParserRouter.download_to_tempfile(processed_file)
    assert File.exist?(tempfile.path)
    assert_equal csv_content, File.read(tempfile.path)

    tempfile.close
    tempfile.unlink
    file.close
    file.unlink
  end
end
