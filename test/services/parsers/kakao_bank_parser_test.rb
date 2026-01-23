require "test_helper"

class Parsers::KakaoBankParserTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:main_workspace)
    @processed_file = processed_files(:pending_file)
    @processed_file.update!(filename: "kakao_statement.xlsx")
  end

  test "returns kakao_bank as institution identifier" do
    parser = Parsers::KakaoBankParser.new(@processed_file)
    assert_equal "kakao_bank", parser.send(:institution_identifier)
  end

  test "identify_columns finds all columns" do
    parser = Parsers::KakaoBankParser.new(@processed_file)
    header_row = [ "거래일시", "거래구분", "내용", "출금", "입금" ]

    result = parser.send(:identify_columns, header_row)

    assert_equal 0, result[:date]
    assert_equal 1, result[:type]
    assert_equal 2, result[:merchant]
    assert_equal 3, result[:outgoing]
    assert_equal 4, result[:incoming]
  end

  test "identify_columns handles nil header_row" do
    parser = Parsers::KakaoBankParser.new(@processed_file)

    result = parser.send(:identify_columns, nil)
    assert_equal({}, result)
  end

  test "identify_columns handles empty header_row" do
    parser = Parsers::KakaoBankParser.new(@processed_file)

    result = parser.send(:identify_columns, [])
    assert_equal({}, result)
  end

  test "parse_row_with_headers extracts data" do
    parser = Parsers::KakaoBankParser.new(@processed_file)
    headers = { date: 0, merchant: 2, outgoing: 3 }
    row = [ "2024.01.15 10:30", nil, "테스트가맹점", "10,000", "" ]

    result = parser.send(:parse_row_with_headers, row, headers)

    assert_not_nil result
    assert_equal Date.new(2024, 1, 15), result[:date]
    assert_equal "테스트가맹점", result[:merchant]
    assert_equal 10000, result[:amount]
  end

  test "parse_row_with_headers skips incoming transactions" do
    parser = Parsers::KakaoBankParser.new(@processed_file)
    headers = { date: 0, type: 1, merchant: 2, outgoing: 3 }
    row = [ "2024.01.15", "입금", "월급", "", "3,000,000" ]

    result = parser.send(:parse_row_with_headers, row, headers)
    assert_nil result
  end

  test "parse_row_with_headers skips 수입 type transactions" do
    parser = Parsers::KakaoBankParser.new(@processed_file)
    headers = { date: 0, type: 1, merchant: 2, outgoing: 3 }
    row = [ "2024.01.15", "수입", "이자", "", "100" ]

    result = parser.send(:parse_row_with_headers, row, headers)
    assert_nil result
  end

  test "parse_row_with_headers returns nil without date" do
    parser = Parsers::KakaoBankParser.new(@processed_file)
    headers = { date: 0, merchant: 2, outgoing: 3 }
    row = [ "invalid", nil, "테스트", "10,000", "" ]

    result = parser.send(:parse_row_with_headers, row, headers)
    assert_nil result
  end

  test "parse_row_with_headers returns nil without merchant" do
    parser = Parsers::KakaoBankParser.new(@processed_file)
    headers = { date: 0, merchant: 2, outgoing: 3 }
    row = [ "2024.01.15", nil, "", "10,000", "" ]

    result = parser.send(:parse_row_with_headers, row, headers)
    assert_nil result
  end

  test "parse_row_with_headers uses amount column fallback" do
    parser = Parsers::KakaoBankParser.new(@processed_file)
    headers = { date: 0, merchant: 2, amount: 3 }
    row = [ "2024.01.15", nil, "테스트", "5,000" ]

    result = parser.send(:parse_row_with_headers, row, headers)
    assert_equal 5000, result[:amount]
  end

  test "find_amount_in_row finds maximum amount" do
    parser = Parsers::KakaoBankParser.new(@processed_file)
    row = [ "2024.01.15", "출금", "테스트", "5,000", "10,000" ]

    result = parser.send(:find_amount_in_row, row)
    assert_equal 10000, result
  end

  test "find_amount_in_row returns 0 when no amounts" do
    parser = Parsers::KakaoBankParser.new(@processed_file)
    row = [ "날짜", "출금", "테스트", nil, nil ]

    result = parser.send(:find_amount_in_row, row)
    assert_equal 0, result
  end

  test "find_data_start_row_csv finds header row" do
    parser = Parsers::KakaoBankParser.new(@processed_file)
    csv = [
      [ "카카오뱅크 거래내역" ],
      [ "거래일시", "내용", "금액" ],
      [ "2024.01.15", "테스트", "10000" ]
    ]

    result = parser.send(:find_data_start_row_csv, csv)
    assert_equal 2, result
  end

  test "find_data_start_row_csv returns default when no header" do
    parser = Parsers::KakaoBankParser.new(@processed_file)
    csv = [
      [ "No", "Header", "Here" ],
      [ "Data", "Row", "1" ]
    ]

    result = parser.send(:find_data_start_row_csv, csv)
    assert_equal 2, result
  end

  test "identify_columns finds date column with 일자 keyword" do
    parser = Parsers::KakaoBankParser.new(@processed_file)
    header_row = [ "거래일자", "적요", "금액" ]

    result = parser.send(:identify_columns, header_row)

    assert_equal 0, result[:date]
  end

  test "identify_columns finds date column with 날짜 keyword" do
    parser = Parsers::KakaoBankParser.new(@processed_file)
    header_row = [ "날짜", "적요", "금액" ]

    result = parser.send(:identify_columns, header_row)

    assert_equal 0, result[:date]
  end

  test "identify_columns finds merchant with 적요 keyword" do
    parser = Parsers::KakaoBankParser.new(@processed_file)
    header_row = [ "거래일시", "적요", "출금" ]

    result = parser.send(:identify_columns, header_row)

    assert_equal 1, result[:merchant]
  end

  test "identify_columns finds merchant with 메모 keyword" do
    parser = Parsers::KakaoBankParser.new(@processed_file)
    header_row = [ "거래일시", "메모", "출금" ]

    result = parser.send(:identify_columns, header_row)

    assert_equal 1, result[:merchant]
  end

  test "identify_columns finds type with 유형 keyword" do
    parser = Parsers::KakaoBankParser.new(@processed_file)
    header_row = [ "거래일시", "유형", "내용" ]

    result = parser.send(:identify_columns, header_row)

    assert_equal 1, result[:type]
  end

  test "identify_columns finds outgoing with 지출 keyword" do
    parser = Parsers::KakaoBankParser.new(@processed_file)
    header_row = [ "거래일시", "적요", "지출", "수입" ]

    result = parser.send(:identify_columns, header_row)

    assert_equal 2, result[:outgoing]
  end

  test "identify_columns finds incoming with 수입 keyword" do
    parser = Parsers::KakaoBankParser.new(@processed_file)
    header_row = [ "거래일시", "적요", "지출", "수입" ]

    result = parser.send(:identify_columns, header_row)

    assert_equal 3, result[:incoming]
  end

  test "identify_columns finds amount column" do
    parser = Parsers::KakaoBankParser.new(@processed_file)
    header_row = [ "거래일시", "적요", "금액" ]

    result = parser.send(:identify_columns, header_row)

    assert_equal 2, result[:amount]
  end

  test "identify_columns skips nil cells" do
    parser = Parsers::KakaoBankParser.new(@processed_file)
    header_row = [ nil, "거래일시", nil, "적요" ]

    result = parser.send(:identify_columns, header_row)

    assert_equal 1, result[:date]
    assert_equal 3, result[:merchant]
  end

  test "parse_row_with_headers uses default columns when headers empty" do
    parser = Parsers::KakaoBankParser.new(@processed_file)
    headers = {}
    row = [ "2024.01.15", nil, "테스트가맹점", "10,000" ]

    result = parser.send(:parse_row_with_headers, row, headers)

    assert_not_nil result
    assert_equal Date.new(2024, 1, 15), result[:date]
    assert_equal "테스트가맹점", result[:merchant]
  end

  test "parse_row_with_headers uses find_amount_in_row as fallback" do
    parser = Parsers::KakaoBankParser.new(@processed_file)
    headers = { date: 0, merchant: 1 }
    row = [ "2024.01.15", "테스트", "5,000", "10,000" ]

    result = parser.send(:parse_row_with_headers, row, headers)

    # Should find max amount from row
    assert_equal 10000, result[:amount]
  end

  test "parse_row_with_headers returns nil with zero amount" do
    parser = Parsers::KakaoBankParser.new(@processed_file)
    headers = { date: 0, merchant: 1, outgoing: 2 }
    row = [ "2024.01.15", "테스트", "0", "" ]

    result = parser.send(:parse_row_with_headers, row, headers)
    assert_nil result
  end

  test "find_data_start_row_csv finds 일시 header" do
    parser = Parsers::KakaoBankParser.new(@processed_file)
    csv = [
      [ "카카오뱅크" ],
      [ "일시", "메모", "금액" ],
      [ "2024.01.15", "테스트", "10000" ]
    ]

    result = parser.send(:find_data_start_row_csv, csv)
    assert_equal 2, result
  end
end
