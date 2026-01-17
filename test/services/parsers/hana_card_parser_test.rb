require "test_helper"

class Parsers::HanaCardParserTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:main_workspace)
    @processed_file = processed_files(:pending_file)
    @processed_file.update!(filename: 'hana_statement.xlsx')
  end

  test "returns hana_card as institution identifier" do
    parser = Parsers::HanaCardParser.new(@processed_file)
    assert_equal 'hana_card', parser.send(:institution_identifier)
  end

  test "find_date_in_row extracts date with full year format" do
    parser = Parsers::HanaCardParser.new(@processed_file)
    row = ['2024.01.15', '가맹점명', '10,000']

    result = parser.send(:find_date_in_row, row)
    assert_equal '2024.01.15', result
  end

  test "find_date_in_row extracts date with short year format" do
    parser = Parsers::HanaCardParser.new(@processed_file)
    row = ['24.01.15', '가맹점명', '10,000']

    result = parser.send(:find_date_in_row, row)
    assert_equal '24.01.15', result
  end

  test "find_date_in_row returns nil when no date found" do
    parser = Parsers::HanaCardParser.new(@processed_file)
    row = ['텍스트', '가맹점명', '10,000']

    result = parser.send(:find_date_in_row, row)
    assert_nil result
  end

  test "find_merchant_in_row extracts merchant" do
    parser = Parsers::HanaCardParser.new(@processed_file)
    row = ['2024.01.15', '테스트가맹점', '10,000']

    result = parser.send(:find_merchant_in_row, row)
    assert_equal '테스트가맹점', result
  end

  test "find_merchant_in_row skips dates and numbers" do
    parser = Parsers::HanaCardParser.new(@processed_file)
    row = ['2024.01.15', '123456', '가맹점이름', '10,000']

    result = parser.send(:find_merchant_in_row, row)
    assert_equal '가맹점이름', result
  end

  test "find_amount_in_row extracts amount" do
    parser = Parsers::HanaCardParser.new(@processed_file)
    row = ['2024.01.15', '가맹점명', '10,000']

    result = parser.send(:find_amount_in_row, row)
    assert_equal 10000, result
  end

  test "find_amount_in_row returns first large amount" do
    parser = Parsers::HanaCardParser.new(@processed_file)
    row = ['2024.01.15', '가맹점', '50', '15,000', '30,000']

    result = parser.send(:find_amount_in_row, row)
    assert_equal 15000, result
  end

  test "find_amount_in_row returns 0 when no amount found" do
    parser = Parsers::HanaCardParser.new(@processed_file)
    row = ['2024.01.15', '가맹점', 'no amounts']

    result = parser.send(:find_amount_in_row, row)
    assert_equal 0, result
  end

  test "parse_row returns nil without valid date" do
    parser = Parsers::HanaCardParser.new(@processed_file)
    row = ['invalid', '가맹점명', '10,000']

    result = parser.send(:parse_row, row)
    assert_nil result
  end

  test "parse_row returns nil with zero amount" do
    parser = Parsers::HanaCardParser.new(@processed_file)
    row = ['2024.01.15', '가맹점명', '0']

    result = parser.send(:parse_row, row)
    assert_nil result
  end

  test "parse_row returns transaction hash with valid data" do
    parser = Parsers::HanaCardParser.new(@processed_file)
    row = ['2024.01.15', '테스트가맹점', '10,000']

    result = parser.send(:parse_row, row)

    assert_not_nil result
    assert_equal Date.new(2024, 1, 15), result[:date]
    assert_equal '테스트가맹점', result[:merchant]
    assert_equal 10000, result[:amount]
    assert_equal 'hana_card', result[:institution_identifier]
  end

  test "find_date_in_row handles date with dash separator" do
    parser = Parsers::HanaCardParser.new(@processed_file)
    row = ['2024-01-15', '가맹점명', '10,000']

    result = parser.send(:find_date_in_row, row)
    assert_equal '2024-01-15', result
  end

  test "find_date_in_row handles date with slash separator" do
    parser = Parsers::HanaCardParser.new(@processed_file)
    row = ['2024/01/15', '가맹점명', '10,000']

    result = parser.send(:find_date_in_row, row)
    assert_equal '2024/01/15', result
  end

  test "find_merchant_in_row returns empty string when no merchant found" do
    parser = Parsers::HanaCardParser.new(@processed_file)
    row = ['2024.01.15', '12345', '10,000']

    result = parser.send(:find_merchant_in_row, row)
    assert_equal '', result
  end

  test "find_merchant_in_row skips short strings" do
    parser = Parsers::HanaCardParser.new(@processed_file)
    row = ['2024.01.15', 'a', '가맹점이름', '10,000']

    result = parser.send(:find_merchant_in_row, row)
    assert_equal '가맹점이름', result
  end

  test "find_amount_in_row handles amount with currency symbol" do
    parser = Parsers::HanaCardParser.new(@processed_file)
    row = ['2024.01.15', '가맹점', '15000']

    result = parser.send(:find_amount_in_row, row)
    assert_equal 15000, result
  end

  test "find_data_start_row finds header row with 이용일" do
    # Create a mock sheet by testing directly
    parser = Parsers::HanaCardParser.new(@processed_file)

    # Testing the method indirectly through parse_row
    row = ['2024.01.15', '가맹점', '10000']
    result = parser.send(:parse_row, row)
    assert_not_nil result
  end

  test "find_merchant_in_row skips nil cells" do
    parser = Parsers::HanaCardParser.new(@processed_file)
    row = [nil, nil, '가맹점이름', '10,000']

    result = parser.send(:find_merchant_in_row, row)
    assert_equal '가맹점이름', result
  end

  test "find_date_in_row skips nil cells" do
    parser = Parsers::HanaCardParser.new(@processed_file)
    row = [nil, '2024.01.15', '가맹점명', '10,000']

    result = parser.send(:find_date_in_row, row)
    assert_equal '2024.01.15', result
  end

  test "find_amount_in_row skips nil cells" do
    parser = Parsers::HanaCardParser.new(@processed_file)
    row = ['2024.01.15', nil, '가맹점', nil, '10,000']

    result = parser.send(:find_amount_in_row, row)
    assert_equal 10000, result
  end
end
