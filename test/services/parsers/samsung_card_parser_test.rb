require "test_helper"

class Parsers::SamsungCardParserTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:main_workspace)
    @processed_file = processed_files(:pending_file)
    @processed_file.update!(filename: "samsungcard_20250626.xlsx")
  end

  test "returns samsung_card as institution identifier" do
    parser = Parsers::SamsungCardParser.new(@processed_file)
    assert_equal "samsung_card", parser.send(:institution_identifier)
  end

  test "parse_samsung_date parses YYYYMMDD format" do
    parser = Parsers::SamsungCardParser.new(@processed_file)

    result = parser.send(:parse_samsung_date, "20250927")

    assert_equal Date.new(2025, 9, 27), result
  end

  test "parse_samsung_date returns nil for blank input" do
    parser = Parsers::SamsungCardParser.new(@processed_file)

    result = parser.send(:parse_samsung_date, "")
    assert_nil result

    result = parser.send(:parse_samsung_date, nil)
    assert_nil result
  end

  test "parse_row extracts one-time payment data" do
    parser = Parsers::SamsungCardParser.new(@processed_file)
    # 컬럼: 이용일, 이용구분, 가맹점, 이용금액, 총할부금액, 이용혜택, 혜택금액, 개월, 회차, 원금, 이자/수수료, 포인트명, 적립금액, 입금후잔액
    row = [ "20250529", "본 인 985", "스팟마트", "139,050", "", " ", "", "", "", 139050.0, 0.0, "", 0.0, 0.0 ]

    result = parser.send(:parse_row, row, "one_time")

    assert_not_nil result
    assert_equal Date.new(2025, 5, 29), result[:date]
    assert_equal "스팟마트", result[:merchant]
    assert_equal 139050, result[:amount]
    assert_equal "one_time", result[:payment_type]
    assert_nil result[:installment_month]
    assert_nil result[:installment_total]
  end

  test "parse_row extracts installment payment data" do
    parser = Parsers::SamsungCardParser.new(@processed_file)
    row = [ "20250927", "본 인 985", "말레이시아 에어라인스 BSP", "1,835,800", "", "이자면제", "-14,935", "5", "3", 367100.0, 0.0, "", 0.0, 734200.0 ]

    result = parser.send(:parse_row, row, "installment")

    assert_not_nil result
    assert_equal Date.new(2025, 9, 27), result[:date]
    assert_equal "말레이시아 에어라인스 BSP", result[:merchant]
    assert_equal 367100, result[:amount]
    assert_equal "installment", result[:payment_type]
    assert_equal 3, result[:installment_month]
    assert_equal 5, result[:installment_total]
  end

  test "parse_row returns nil for summary rows" do
    parser = Parsers::SamsungCardParser.new(@processed_file)
    row = [ "", "", "일시불합계", " ", " ", "", " ", " ", " ", 139050.0, 0.0, "", 0.0, 0.0 ]

    result = parser.send(:parse_row, row, "one_time")
    assert_nil result
  end

  test "parse_row returns nil for rows without date" do
    parser = Parsers::SamsungCardParser.new(@processed_file)
    row = [ "", "본 인 985", "가맹점", "10,000", "", "", "", "", "", 10000.0, 0.0, "", 0.0, 0.0 ]

    result = parser.send(:parse_row, row, "one_time")
    assert_nil result
  end

  test "parse_row returns nil for rows with zero amount" do
    parser = Parsers::SamsungCardParser.new(@processed_file)
    row = [ "20250529", "본 인 985", "가맹점", "0", "", "", "", "", "", 0.0, 0.0, "", 0.0, 0.0 ]

    result = parser.send(:parse_row, row, "one_time")
    assert_nil result
  end

  test "determine_payment_type returns installment for 할부 sheet" do
    parser = Parsers::SamsungCardParser.new(@processed_file)

    assert_equal "installment", parser.send(:determine_payment_type, "할부")
  end

  test "determine_payment_type returns one_time for 일시불 sheet" do
    parser = Parsers::SamsungCardParser.new(@processed_file)

    assert_equal "one_time", parser.send(:determine_payment_type, "일시불")
  end

  test "extract_amount handles numeric values" do
    parser = Parsers::SamsungCardParser.new(@processed_file)

    assert_equal 139050, parser.send(:extract_amount, 139050.0)
    assert_equal 139050, parser.send(:extract_amount, 139050)
  end

  test "extract_amount handles string values with commas" do
    parser = Parsers::SamsungCardParser.new(@processed_file)

    assert_equal 139050, parser.send(:extract_amount, "139,050")
    assert_equal 1835800, parser.send(:extract_amount, "1,835,800")
  end

  test "extract_amount returns 0 for blank values" do
    parser = Parsers::SamsungCardParser.new(@processed_file)

    assert_equal 0, parser.send(:extract_amount, "")
    assert_equal 0, parser.send(:extract_amount, nil)
  end
end
