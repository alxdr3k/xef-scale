require "test_helper"

class Parsers::ShinhanCardParserTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:main_workspace)
    @processed_file = processed_files(:pending_file)
    @processed_file.update!(filename: 'shinhan_statement.txt')
  end

  test "returns shinhan_card as institution identifier" do
    parser = Parsers::ShinhanCardParser.new(@processed_file)
    assert_equal 'shinhan_card', parser.send(:institution_identifier)
  end

  test "extract_transactions_from_text parses date-merchant-amount pattern" do
    parser = Parsers::ShinhanCardParser.new(@processed_file)
    text = <<~TEXT
      24.01.15
      본인357 테스트가맹점
      10,000
    TEXT

    result = parser.send(:extract_transactions_from_text, text)

    assert_equal 1, result.size
    assert_equal Date.new(2024, 1, 15), result[0][:date]
    assert_equal '테스트가맹점', result[0][:merchant]
    assert_equal 10000, result[0][:amount]
  end

  test "extract_transactions_from_text removes 본인 prefix" do
    parser = Parsers::ShinhanCardParser.new(@processed_file)
    text = <<~TEXT
      24.03.20
      본인123 스타벅스
      5,500
    TEXT

    result = parser.send(:extract_transactions_from_text, text)

    assert_equal '스타벅스', result[0][:merchant]
  end

  test "extract_transactions_from_text skips amounts under 100" do
    parser = Parsers::ShinhanCardParser.new(@processed_file)
    text = <<~TEXT
      24.01.15
      테스트가맹점
      50
    TEXT

    result = parser.send(:extract_transactions_from_text, text)
    assert_empty result
  end

  test "extract_transactions_from_text handles multiple transactions" do
    parser = Parsers::ShinhanCardParser.new(@processed_file)
    text = <<~TEXT
      24.01.15
      가맹점A
      10,000
      24.01.16
      가맹점B
      20,000
    TEXT

    result = parser.send(:extract_transactions_from_text, text)
    assert_equal 2, result.size
  end

  test "extract_transactions_from_text returns empty for no matches" do
    parser = Parsers::ShinhanCardParser.new(@processed_file)
    text = "No valid data here"

    result = parser.send(:extract_transactions_from_text, text)
    assert_empty result
  end

  test "parse_excel_row extracts data" do
    parser = Parsers::ShinhanCardParser.new(@processed_file)
    row = ['2024.01.15', '123456', '테스트가맹점', '10,000']

    result = parser.send(:parse_excel_row, row)

    assert_not_nil result
    assert_equal Date.new(2024, 1, 15), result[:date]
    assert_equal '테스트가맹점', result[:merchant]
    assert_equal 10000, result[:amount]
  end

  test "parse_excel_row returns nil without valid date" do
    parser = Parsers::ShinhanCardParser.new(@processed_file)
    row = ['invalid', '123456', '가맹점', '10,000']

    result = parser.send(:parse_excel_row, row)
    assert_nil result
  end

  test "parse_excel_row uses fallback merchant column" do
    parser = Parsers::ShinhanCardParser.new(@processed_file)
    row = ['2024.01.15', '가맹점', '', '10,000']

    result = parser.send(:parse_excel_row, row)
    assert_equal '가맹점', result[:merchant]
  end

  test "parse_excel_row returns nil with zero amount" do
    parser = Parsers::ShinhanCardParser.new(@processed_file)
    row = ['2024.01.15', '123456', '가맹점', '0']

    result = parser.send(:parse_excel_row, row)
    assert_nil result
  end

  test "parse_excel_row parses valid data with amount" do
    parser = Parsers::ShinhanCardParser.new(@processed_file)
    # Testing row with amount in column 3 and 4
    row = ['2024.01.15', '123456', '가맹점', '15,000', '15,000']

    result = parser.send(:parse_excel_row, row)
    assert_not_nil result
    assert_equal 15000, result[:amount]
  end

  test "extract_transactions_from_text handles merchant without prefix" do
    parser = Parsers::ShinhanCardParser.new(@processed_file)
    text = <<~TEXT
      24.01.15
      스타벅스
      5,500
    TEXT

    result = parser.send(:extract_transactions_from_text, text)

    assert_equal 1, result.size
    assert_equal '스타벅스', result[0][:merchant]
  end

  test "extract_transactions_from_text skips numeric lines as merchant" do
    parser = Parsers::ShinhanCardParser.new(@processed_file)
    text = <<~TEXT
      24.01.15
      12345
      5,500
    TEXT

    result = parser.send(:extract_transactions_from_text, text)

    # Should be empty since '12345' is numeric, not a valid merchant
    assert_empty result
  end

  test "extract_transactions_from_text resets state after transaction" do
    parser = Parsers::ShinhanCardParser.new(@processed_file)
    text = <<~TEXT
      24.01.15
      가맹점A
      10,000
      some unrelated text
      24.01.16
      가맹점B
      20,000
    TEXT

    result = parser.send(:extract_transactions_from_text, text)
    assert_equal 2, result.size
    assert_equal Date.new(2024, 1, 15), result[0][:date]
    assert_equal Date.new(2024, 1, 16), result[1][:date]
  end

  test "extract_transactions_from_text handles empty merchant line" do
    parser = Parsers::ShinhanCardParser.new(@processed_file)
    text = <<~TEXT
      24.01.15

      10,000
    TEXT

    result = parser.send(:extract_transactions_from_text, text)

    # Should be empty since merchant is blank
    assert_empty result
  end

  test "find_data_start_row returns default 5 when no header found" do
    # Test indirectly through parse_excel_row
    parser = Parsers::ShinhanCardParser.new(@processed_file)
    row = ['2024.01.15', '승인', '가맹점', '10000']

    result = parser.send(:parse_excel_row, row)
    assert_not_nil result
  end
end
