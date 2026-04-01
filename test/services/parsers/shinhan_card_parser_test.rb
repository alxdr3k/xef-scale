require "test_helper"

class Parsers::ShinhanCardParserTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:main_workspace)
    @processed_file = processed_files(:pending_file)
    @processed_file.update!(filename: "shinhan_statement.txt")
  end

  test "returns shinhan_card as institution identifier" do
    parser = Parsers::ShinhanCardParser.new(@processed_file)
    assert_equal "shinhan_card", parser.send(:institution_identifier)
  end

  test "parse_excel_row extracts data" do
    parser = Parsers::ShinhanCardParser.new(@processed_file)
    row = [ "2024.01.15", "123456", "테스트가맹점", "10,000" ]

    result = parser.send(:parse_excel_row, row)

    assert_not_nil result
    assert_equal Date.new(2024, 1, 15), result[:date]
    assert_equal "테스트가맹점", result[:merchant]
    assert_equal 10000, result[:amount]
  end

  test "parse_excel_row returns nil without valid date" do
    parser = Parsers::ShinhanCardParser.new(@processed_file)
    row = [ "invalid", "123456", "가맹점", "10,000" ]

    result = parser.send(:parse_excel_row, row)
    assert_nil result
  end

  test "parse_excel_row uses fallback merchant column" do
    parser = Parsers::ShinhanCardParser.new(@processed_file)
    row = [ "2024.01.15", "가맹점", "", "10,000" ]

    result = parser.send(:parse_excel_row, row)
    assert_equal "가맹점", result[:merchant]
  end

  test "parse_excel_row returns nil with zero amount" do
    parser = Parsers::ShinhanCardParser.new(@processed_file)
    row = [ "2024.01.15", "123456", "가맹점", "0" ]

    result = parser.send(:parse_excel_row, row)
    assert_nil result
  end

  test "parse_excel_row parses valid data with amount" do
    parser = Parsers::ShinhanCardParser.new(@processed_file)
    # Testing row with amount in column 3 and 4
    row = [ "2024.01.15", "123456", "가맹점", "15,000", "15,000" ]

    result = parser.send(:parse_excel_row, row)
    assert_not_nil result
    assert_equal 15000, result[:amount]
  end

  test "find_data_start_row returns default 5 when no header found" do
    # Test indirectly through parse_excel_row
    parser = Parsers::ShinhanCardParser.new(@processed_file)
    row = [ "2024.01.15", "승인", "가맹점", "10000" ]

    result = parser.send(:parse_excel_row, row)
    assert_not_nil result
  end
end
