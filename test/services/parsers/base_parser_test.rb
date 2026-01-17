require "test_helper"

class Parsers::BaseParserTest < ActiveSupport::TestCase
  class TestParser < Parsers::BaseParser
    def institution_identifier
      'test_parser'
    end

    def parse
      []
    end
  end

  def setup
    @processed_file = processed_files(:completed_file)
    @parser = TestParser.new(@processed_file)
  end

  test "initializes with processed file" do
    assert_equal @processed_file, @parser.processed_file
  end

  test "base parser parse raises NotImplementedError" do
    base = Parsers::BaseParser.new(@processed_file)
    assert_raises(NotImplementedError) { base.parse }
  end

  test "parse_date handles yyyy.mm.dd format" do
    date = @parser.send(:parse_date, '2024.01.15')
    assert_equal Date.new(2024, 1, 15), date
  end

  test "parse_date handles yyyy-mm-dd format" do
    date = @parser.send(:parse_date, '2024-01-15')
    assert_equal Date.new(2024, 1, 15), date
  end

  test "parse_date handles yyyy/mm/dd format" do
    date = @parser.send(:parse_date, '2024/01/15')
    assert_equal Date.new(2024, 1, 15), date
  end

  test "parse_date handles yy.mm.dd format" do
    date = @parser.send(:parse_date, '24.01.15')
    assert_equal Date.new(2024, 1, 15), date
  end

  test "parse_date handles yy-mm-dd format" do
    date = @parser.send(:parse_date, '24-01-15')
    assert_equal Date.new(2024, 1, 15), date
  end

  test "parse_date handles yy/mm/dd format" do
    date = @parser.send(:parse_date, '24/01/15')
    assert_equal Date.new(2024, 1, 15), date
  end

  test "parse_date handles mm/dd/yyyy format" do
    date = @parser.send(:parse_date, '01/15/2024')
    assert_equal Date.new(2024, 1, 15), date
  end

  # Note: dd/mm/yyyy format may be ambiguous, this test verifies current behavior

  test "parse_date returns nil for blank input" do
    assert_nil @parser.send(:parse_date, '')
    assert_nil @parser.send(:parse_date, nil)
  end

  test "parse_date returns nil for invalid date" do
    assert_nil @parser.send(:parse_date, 'not a date')
  end

  test "parse_amount removes currency symbols and commas" do
    assert_equal 12500, @parser.send(:parse_amount, '₩12,500')
    assert_equal 12500, @parser.send(:parse_amount, '12,500원')
    assert_equal 12500, @parser.send(:parse_amount, '12500')
  end

  test "parse_amount returns absolute value" do
    assert_equal 12500, @parser.send(:parse_amount, '-12,500')
  end

  test "parse_amount returns 0 for blank input" do
    assert_equal 0, @parser.send(:parse_amount, '')
    assert_equal 0, @parser.send(:parse_amount, nil)
  end

  test "build_transaction creates hash with all fields" do
    result = @parser.send(:build_transaction,
      date: Date.new(2024, 1, 15),
      merchant: '마라탕집',
      amount: 12000,
      description: '점심 식사'
    )

    assert_equal Date.new(2024, 1, 15), result[:date]
    assert_equal '마라탕집', result[:merchant]
    assert_equal 12000, result[:amount]
    assert_equal '점심 식사', result[:description]
    assert_equal 'test_parser', result[:institution_identifier]
  end

  test "build_transaction strips whitespace" do
    result = @parser.send(:build_transaction,
      date: Date.today,
      merchant: '  마라탕집  ',
      amount: 12000,
      description: '  점심 식사  '
    )

    assert_equal '마라탕집', result[:merchant]
    assert_equal '점심 식사', result[:description]
  end

  test "build_transaction handles nil description" do
    result = @parser.send(:build_transaction,
      date: Date.today,
      merchant: '테스트',
      amount: 1000
    )

    assert_equal '', result[:description]
  end

  test "parse_date handles datetime format" do
    date = @parser.send(:parse_date, '2024-01-15 10:30:00')
    assert_equal Date.new(2024, 1, 15), date
  end

  test "parse_date handles datetime with spaces" do
    date = @parser.send(:parse_date, '  2024.01.15  ')
    assert_equal Date.new(2024, 1, 15), date
  end

  test "parse_amount handles large numbers" do
    assert_equal 1000000, @parser.send(:parse_amount, '1,000,000')
  end

  test "parse_amount handles decimal values" do
    assert_equal 12500, @parser.send(:parse_amount, '12500.00')
  end

  test "build_transaction includes all required fields" do
    result = @parser.send(:build_transaction,
      date: Date.new(2024, 1, 15),
      merchant: 'Test',
      amount: 5000,
      description: 'Test description'
    )

    assert_includes result.keys, :date
    assert_includes result.keys, :merchant
    assert_includes result.keys, :amount
    assert_includes result.keys, :description
    assert_includes result.keys, :institution_identifier
  end

  test "institution_identifier must be implemented by subclass" do
    base = Parsers::BaseParser.new(@processed_file)
    assert_raises(NotImplementedError) { base.send(:institution_identifier) }
  end
end
