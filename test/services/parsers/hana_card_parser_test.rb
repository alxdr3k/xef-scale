require "test_helper"

class Parsers::HanaCardParserTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:main_workspace)
    @processed_file = processed_files(:pending_file)
    @processed_file.update!(filename: "hana_statement.xlsx")
  end

  test "returns hana_card as institution identifier" do
    parser = Parsers::HanaCardParser.new(@processed_file)
    assert_equal "hana_card", parser.send(:institution_identifier)
  end

  test "parse_transaction_row returns nil without valid date" do
    parser = Parsers::HanaCardParser.new(@processed_file)
    row = ["invalid", "가맹점명", 10000]

    result = parser.send(:parse_transaction_row, row)
    assert_nil result
  end

  test "parse_transaction_row returns nil with zero amount" do
    parser = Parsers::HanaCardParser.new(@processed_file)
    row = ["2024.01.15", "가맹점명", 0]

    result = parser.send(:parse_transaction_row, row)
    assert_nil result
  end

  test "parse_transaction_row returns nil with blank merchant" do
    parser = Parsers::HanaCardParser.new(@processed_file)
    row = ["2024.01.15", "", 10000]

    result = parser.send(:parse_transaction_row, row)
    assert_nil result
  end

  test "parse_transaction_row returns transaction hash with valid data" do
    parser = Parsers::HanaCardParser.new(@processed_file)
    row = ["2024.01.15", "테스트가맹점", 10000]

    result = parser.send(:parse_transaction_row, row)

    assert_not_nil result
    assert_equal Date.new(2024, 1, 15), result[:date]
    assert_equal "테스트가맹점", result[:merchant]
    assert_equal 10000, result[:amount]
    assert_equal "hana_card", result[:institution_identifier]
  end

  test "parse_transaction_row handles integer amount" do
    parser = Parsers::HanaCardParser.new(@processed_file)
    row = ["2024.01.15", "가맹점", 15000]

    result = parser.send(:parse_transaction_row, row)
    assert_equal 15000, result[:amount]
  end

  test "find_header_row returns nil when no header found" do
    parser = Parsers::HanaCardParser.new(@processed_file)

    # Create a simple struct that responds to row method
    mock_sheet = Object.new
    def mock_sheet.row(_num)
      ["other_text", "data"]
    end

    result = parser.send(:find_header_row, mock_sheet)
    assert_nil result
  end
end
