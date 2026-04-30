require "test_helper"

class ImageStatementParserTest < ActiveSupport::TestCase
  PNG_MAGIC = "\x89PNG\r\n\x1A\n\x00\x00\x00\rIHDR".b.freeze

  setup do
    @workspace = workspaces(:main_workspace)
    @processed_file = @workspace.processed_files.build(
      filename: "statement.png",
      original_filename: "statement.png",
      status: "pending"
    )
    @processed_file.file.attach(
      io: StringIO.new(PNG_MAGIC),
      filename: "statement.png",
      content_type: "image/png"
    )
    @processed_file.save!
  end

  test "raises for non-image extension" do
    pf = @workspace.processed_files.build(
      filename: "statement.xlsx",
      original_filename: "statement.xlsx",
      status: "pending"
    )
    parser = ImageStatementParser.new(pf, institution_identifier: "shinhan_card")
    assert_raises(ImageStatementParser::UnsupportedFormatError) { parser.parse }
  end

  test "defaults institution_identifier to shinhan_card" do
    parser = ImageStatementParser.new(@processed_file)
    identifier = parser.instance_variable_get(:@institution_identifier)
    assert_equal "shinhan_card", identifier
  end

  test "normalizes raw transactions and tags them with institution_identifier" do
    parser = ImageStatementParser.new(@processed_file, institution_identifier: "shinhan_card")
    raw = [
      { date: "2026.01.15", merchant: "  스타벅스강남점  ", amount: 5800, payment_type: "lump_sum" },
      { date: "invalid-date", merchant: "무시", amount: 1000 }
    ]
    result = parser.send(:normalize, raw)

    assert_equal 1, result.size
    tx = result.first
    assert_equal Date.new(2026, 1, 15), tx[:date]
    assert_equal "스타벅스강남점", tx[:merchant]
    assert_equal 5800, tx[:amount]
    assert_equal "lump_sum", tx[:payment_type]
    assert_equal "shinhan_card", tx[:institution_identifier]
    assert_nil tx[:source_institution_raw]
  end

  test "normalizes Hash result wrapper with :transactions key" do
    parser = ImageStatementParser.new(@processed_file, institution_identifier: "shinhan_card")
    raw = { transactions: [ { date: "2026.01.15", merchant: "X", amount: 1000 } ] }
    result = parser.send(:normalize, raw)
    assert_equal 1, result.size
  end

  test "captures incomplete transactions from parser result wrapper" do
    parser = ImageStatementParser.new(@processed_file, institution_identifier: "shinhan_card")
    raw = {
      transactions: [ { date: "2026.01.15", merchant: "완성", amount: 1000 } ],
      incomplete_transactions: [
        { date: nil, merchant: "네이버페이", amount: 12_000, missing_fields: [ "date" ] }
      ]
    }

    result = parser.send(:normalize, raw)

    assert_equal 1, result.size
    assert_equal 1, parser.incomplete_transactions.size
    incomplete = parser.incomplete_transactions.first
    assert_nil incomplete[:date]
    assert_equal "네이버페이", incomplete[:merchant]
    assert_equal 12_000, incomplete[:amount]
    assert_equal [ "date" ], incomplete[:missing_fields]
  end

  test "normalizes parser provided source institution separately from institution identifier hint" do
    parser = ImageStatementParser.new(@processed_file, institution_identifier: "shinhan_card")
    raw = [
      { date: "2026.01.15", merchant: "스타벅스", amount: 5800, institution: "KB국민카드" }
    ]

    result = parser.send(:normalize, raw)

    assert_equal 1, result.size
    assert_equal "shinhan_card", result.first[:institution_identifier]
    assert_equal "KB국민카드", result.first[:source_institution_raw]
  end
end
