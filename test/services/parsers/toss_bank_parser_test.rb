require "test_helper"

class Parsers::TossBankParserTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:main_workspace)
    @processed_file = processed_files(:pending_file)
    @processed_file.update!(filename: 'toss_statement.xlsx')
  end

  test "returns toss_bank as institution identifier" do
    parser = Parsers::TossBankParser.new(@processed_file)
    assert_equal 'toss_bank', parser.send(:institution_identifier)
  end

  test "identify_columns finds date column" do
    parser = Parsers::TossBankParser.new(@processed_file)
    header_row = ['거래일시', '내용', '출금', '입금']

    result = parser.send(:identify_columns, header_row)

    assert_equal 0, result[:date]
  end

  test "identify_columns finds merchant column" do
    parser = Parsers::TossBankParser.new(@processed_file)
    header_row = ['거래일', '적요', '금액']

    result = parser.send(:identify_columns, header_row)

    assert_equal 1, result[:merchant]
  end

  test "identify_columns finds outgoing and incoming columns" do
    parser = Parsers::TossBankParser.new(@processed_file)
    header_row = ['날짜', '내용', '출금금액', '입금금액']

    result = parser.send(:identify_columns, header_row)

    assert_equal 2, result[:outgoing]
    assert_equal 3, result[:incoming]
  end

  test "identify_columns returns empty hash for unrecognized headers" do
    parser = Parsers::TossBankParser.new(@processed_file)
    header_row = ['Column1', 'Column2', 'Column3']

    result = parser.send(:identify_columns, header_row)
    assert_equal({}, result)
  end

  test "parse_row_with_headers extracts data" do
    parser = Parsers::TossBankParser.new(@processed_file)
    headers = { date: 0, merchant: 1, outgoing: 2 }
    row = ['2024.01.15', '테스트가맹점', '10,000']

    result = parser.send(:parse_row_with_headers, row, headers)

    assert_not_nil result
    assert_equal Date.new(2024, 1, 15), result[:date]
    assert_equal '테스트가맹점', result[:merchant]
    assert_equal 10000, result[:amount]
  end

  test "parse_row_with_headers uses amount column as fallback" do
    parser = Parsers::TossBankParser.new(@processed_file)
    headers = { date: 0, merchant: 1, amount: 2 }
    row = ['2024.01.15', '테스트가맹점', '15,000']

    result = parser.send(:parse_row_with_headers, row, headers)

    assert_equal 15000, result[:amount]
  end

  test "parse_row_with_headers uses incoming as fallback" do
    parser = Parsers::TossBankParser.new(@processed_file)
    headers = { date: 0, merchant: 1, incoming: 2 }
    row = ['2024.01.15', '테스트가맹점', '20,000']

    result = parser.send(:parse_row_with_headers, row, headers)

    assert_equal 20000, result[:amount]
  end

  test "parse_row_with_headers returns nil without date" do
    parser = Parsers::TossBankParser.new(@processed_file)
    headers = { date: 0, merchant: 1, outgoing: 2 }
    row = ['invalid', '테스트', '10,000']

    result = parser.send(:parse_row_with_headers, row, headers)
    assert_nil result
  end

  test "parse_row_with_headers returns nil without merchant" do
    parser = Parsers::TossBankParser.new(@processed_file)
    headers = { date: 0, merchant: 1, outgoing: 2 }
    row = ['2024.01.15', '', '10,000']

    result = parser.send(:parse_row_with_headers, row, headers)
    assert_nil result
  end

  test "parse_row_with_headers returns nil with zero amount" do
    parser = Parsers::TossBankParser.new(@processed_file)
    headers = { date: 0, merchant: 1 }
    row = ['2024.01.15', '테스트가맹점', '0']

    result = parser.send(:parse_row_with_headers, row, headers)
    assert_nil result
  end

  test "find_data_start_row_csv finds header row" do
    parser = Parsers::TossBankParser.new(@processed_file)
    csv = [
      ['토스뱅크 거래내역'],
      ['거래일', '적요', '출금'],
      ['2024.01.15', '테스트', '10000']
    ]

    result = parser.send(:find_data_start_row_csv, csv)
    assert_equal 2, result
  end

  test "find_data_start_row_csv returns default when no header found" do
    parser = Parsers::TossBankParser.new(@processed_file)
    csv = [
      ['No', 'Header', 'Here'],
      ['2024.01.15', '테스트', '10000']
    ]

    result = parser.send(:find_data_start_row_csv, csv)
    assert_equal 3, result
  end

  test "identify_columns handles nil cells" do
    parser = Parsers::TossBankParser.new(@processed_file)
    header_row = [nil, '거래일', nil, '내용']

    result = parser.send(:identify_columns, header_row)

    assert_equal 1, result[:date]
    assert_equal 3, result[:merchant]
  end

  test "identify_columns finds date column correctly" do
    parser = Parsers::TossBankParser.new(@processed_file)
    # The identify_columns method checks for: str.include?('일') && (str.include?('거래') || str.include?('날짜'))
    header_row = ['거래일', '적요', '금액']

    result = parser.send(:identify_columns, header_row)

    assert_equal 0, result[:date]
  end

  test "identify_columns finds merchant with 기재 keyword" do
    parser = Parsers::TossBankParser.new(@processed_file)
    header_row = ['거래일', '기재내용', '금액']

    result = parser.send(:identify_columns, header_row)

    assert_equal 1, result[:merchant]
  end

  test "identify_columns finds outgoing with 보낸 keyword" do
    parser = Parsers::TossBankParser.new(@processed_file)
    header_row = ['거래일', '적요', '보낸금액', '받은금액']

    result = parser.send(:identify_columns, header_row)

    assert_equal 2, result[:outgoing]
  end

  test "identify_columns finds incoming with 받은 keyword" do
    parser = Parsers::TossBankParser.new(@processed_file)
    header_row = ['거래일', '적요', '보낸금액', '받은금액']

    result = parser.send(:identify_columns, header_row)

    assert_equal 3, result[:incoming]
  end

  test "parse_row_with_headers returns correct institution identifier" do
    parser = Parsers::TossBankParser.new(@processed_file)
    headers = { date: 0, merchant: 1, outgoing: 2 }
    row = ['2024.01.15', '테스트가맹점', '10,000']

    result = parser.send(:parse_row_with_headers, row, headers)

    assert_equal 'toss_bank', result[:institution_identifier]
  end

  test "parse_row_with_headers uses default columns when headers limited" do
    parser = Parsers::TossBankParser.new(@processed_file)
    headers = { date: 0, merchant: 1, outgoing: 2 }
    row = ['2024.01.15', '테스트가맹점', '10,000']

    result = parser.send(:parse_row_with_headers, row, headers)

    assert_not_nil result
    assert_equal Date.new(2024, 1, 15), result[:date]
  end

  test "parse_row_with_headers returns nil when amount is zero" do
    parser = Parsers::TossBankParser.new(@processed_file)
    headers = { date: 0, merchant: 1 }
    row = ['2024.01.15', '테스트', '0']

    result = parser.send(:parse_row_with_headers, row, headers)
    assert_nil result
  end

  test "find_data_start_row_csv finds 일시 header" do
    parser = Parsers::TossBankParser.new(@processed_file)
    csv = [
      ['토스뱅크'],
      ['일시', '내용', '출금'],
      ['2024.01.15', '테스트', '10000']
    ]

    result = parser.send(:find_data_start_row_csv, csv)
    assert_equal 2, result
  end

  test "find_data_start_row_csv finds 날짜 header" do
    parser = Parsers::TossBankParser.new(@processed_file)
    csv = [
      ['토스뱅크'],
      ['날짜', '내용', '출금'],
      ['2024.01.15', '테스트', '10000']
    ]

    result = parser.send(:find_data_start_row_csv, csv)
    assert_equal 2, result
  end
end
