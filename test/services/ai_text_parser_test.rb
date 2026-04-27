require "test_helper"

class AiTextParserTest < ActiveSupport::TestCase
  # Synthetic Korean financial SMS samples for testing
  SAMPLE_SMS = {
    shinhan_card: "[Web발신]\n신한체크 승인 홍*동\n50,000원 일시불\n03/15 14:30 스타벅스강남점\n누적 1,250,000원",
    kb_card: "[Web발신]\nKB국민카드 승인\n김*수 30,000원 일시불\n03/16 12:00 이마트 역삼점\n잔여한도 4,970,000원",
    hana_card: "[Web발신]\n하나카드승인 박*영\n25,000원 3개월\n03/17 18:45 올리브영 명동점\n누적 800,000원",
    toss_bank: "[토스뱅크] 출금 100,000원\n잔액 2,500,000원\n03/18 09:00 카카오페이",
    shinhan_cancel: "[Web발신]\n신한체크 승인취소 홍*동\n50,000원\n03/15 14:35 스타벅스강남점",
    multiple: "[Web발신]\n신한체크 승인 홍*동\n15,000원 일시불\n03/20 12:00 맥도날드 강남DT\n\n[Web발신]\nKB국민카드 승인\n홍*동 8,500원 일시불\n03/20 13:30 GS25 역삼점"
  }.freeze

  test "raises error without API key" do
    original = ENV["GEMINI_API_KEY"]
    ENV["GEMINI_API_KEY"] = nil

    assert_raises(ArgumentError) { AiTextParser.new }
  ensure
    ENV["GEMINI_API_KEY"] = original
  end

  test "raises ParseError for blank text" do
    parser = AiTextParser.new(api_key: "test_key")
    assert_raises(AiTextParser::ParseError) { parser.parse("") }
    assert_raises(AiTextParser::ParseError) { parser.parse(nil) }
  end

  test "parse returns correct structure on success" do
    parser = AiTextParser.new(api_key: "test_key")

    # Test via direct extract_transactions to avoid network calls
    fake_response = build_gemini_response([
      { date: "2026-03-15", merchant: "스타벅스강남점", amount: 50000,
        institution: "신한카드", payment_type: "lump_sum",
        is_cancel: false, confidence: 0.95 }
    ])

    transactions = parser.send(:extract_transactions, fake_response)
    assert_equal 1, transactions.size
    assert_equal 50000, transactions.first[:amount]
  end

  test "extract_transactions parses valid Gemini response" do
    parser = AiTextParser.new(api_key: "test_key")

    fake_response = {
      "candidates" => [ {
        "content" => {
          "parts" => [ {
            "text" => {
              transactions: [
                {
                  date: "2026-03-15",
                  merchant: "스타벅스강남점",
                  amount: 50000,
                  institution: "신한카드",
                  payment_type: "lump_sum",
                  installment_month: nil,
                  installment_total: nil,
                  is_cancel: false,
                  confidence: 0.95
                }
              ]
            }.to_json
          } ]
        }
      } ]
    }

    transactions = parser.send(:extract_transactions, fake_response)
    assert_equal 1, transactions.size

    tx = transactions.first
    assert_equal Date.new(2026, 3, 15), tx[:date]
    assert_equal "스타벅스강남점", tx[:merchant]
    assert_equal 50000, tx[:amount]
    assert_equal "신한카드", tx[:institution]
    assert_equal "lump_sum", tx[:payment_type]
    assert_equal false, tx[:is_cancel]
    assert_in_delta 0.95, tx[:confidence], 0.01
  end

  test "extract_transactions handles installment payment" do
    parser = AiTextParser.new(api_key: "test_key")

    fake_response = {
      "candidates" => [ {
        "content" => {
          "parts" => [ {
            "text" => {
              transactions: [
                {
                  date: "2026-03-17",
                  merchant: "올리브영 명동점",
                  amount: 25000,
                  institution: "하나카드",
                  payment_type: "installment",
                  installment_month: 1,
                  installment_total: 3,
                  is_cancel: false,
                  confidence: 0.90
                }
              ]
            }.to_json
          } ]
        }
      } ]
    }

    transactions = parser.send(:extract_transactions, fake_response)
    tx = transactions.first
    assert_equal "installment", tx[:payment_type]
    assert_equal 1, tx[:installment_month]
    assert_equal 3, tx[:installment_total]
  end

  test "extract_transactions stores cancellation as negative amount" do
    parser = AiTextParser.new(api_key: "test_key")

    fake_response = {
      "candidates" => [ {
        "content" => {
          "parts" => [ {
            "text" => {
              transactions: [
                {
                  date: "2026-03-15",
                  merchant: "스타벅스강남점",
                  amount: 50000,
                  institution: "신한카드",
                  payment_type: "lump_sum",
                  is_cancel: true,
                  confidence: 0.92
                }
              ]
            }.to_json
          } ]
        }
      } ]
    }

    transactions = parser.send(:extract_transactions, fake_response)
    tx = transactions.first
    assert_equal true, tx[:is_cancel]
    assert_equal(-50000, tx[:amount], "취소 거래는 음수 금액으로 저장되어야 함")
  end

  test "extract_transactions negates even when model returns already-negative amount" do
    parser = AiTextParser.new(api_key: "test_key")

    fake_response = {
      "candidates" => [ {
        "content" => {
          "parts" => [ {
            "text" => {
              transactions: [
                {
                  date: "2026-03-15",
                  merchant: "스타벅스강남점",
                  amount: -50000,
                  institution: "신한카드",
                  payment_type: "lump_sum",
                  is_cancel: true,
                  confidence: 0.92
                }
              ]
            }.to_json
          } ]
        }
      } ]
    }

    tx = parser.send(:extract_transactions, fake_response).first
    assert_equal(-50000, tx[:amount], "모델이 이미 음수를 줬어도 결과는 음수 한 번만 적용")
  end

  test "extract_transactions handles multiple transactions" do
    parser = AiTextParser.new(api_key: "test_key")

    fake_response = {
      "candidates" => [ {
        "content" => {
          "parts" => [ {
            "text" => {
              transactions: [
                {
                  date: "2026-03-20", merchant: "맥도날드 강남DT", amount: 15000,
                  institution: "신한카드", payment_type: "lump_sum",
                  is_cancel: false, confidence: 0.95
                },
                {
                  date: "2026-03-20", merchant: "GS25 역삼점", amount: 8500,
                  institution: "KB국민카드", payment_type: "lump_sum",
                  is_cancel: false, confidence: 0.93
                }
              ]
            }.to_json
          } ]
        }
      } ]
    }

    transactions = parser.send(:extract_transactions, fake_response)
    assert_equal 2, transactions.size
    assert_equal "맥도날드 강남DT", transactions[0][:merchant]
    assert_equal "GS25 역삼점", transactions[1][:merchant]
  end

  test "extract_transactions filters out zero-amount entries" do
    parser = AiTextParser.new(api_key: "test_key")

    fake_response = {
      "candidates" => [ {
        "content" => {
          "parts" => [ {
            "text" => {
              transactions: [
                { date: "2026-03-15", merchant: "스타벅스", amount: 5000,
                  institution: "신한", payment_type: "lump_sum",
                  is_cancel: false, confidence: 0.9 },
                { date: "2026-03-15", merchant: "광고", amount: 0,
                  institution: "없음", payment_type: "lump_sum",
                  is_cancel: false, confidence: 0.1 }
              ]
            }.to_json
          } ]
        }
      } ]
    }

    transactions = parser.send(:extract_transactions, fake_response)
    assert_equal 1, transactions.size
  end

  test "extract_transactions handles malformed JSON gracefully" do
    parser = AiTextParser.new(api_key: "test_key")

    fake_response = {
      "candidates" => [ {
        "content" => {
          "parts" => [ { "text" => "not valid json {{{" } ]
        }
      } ]
    }

    transactions = parser.send(:extract_transactions, fake_response)
    assert_equal [], transactions
  end

  test "extract_transactions handles empty response" do
    parser = AiTextParser.new(api_key: "test_key")

    fake_response = { "candidates" => [] }
    assert_equal [], parser.send(:extract_transactions, fake_response)

    fake_response2 = { "candidates" => [ { "content" => { "parts" => [ { "text" => "" } ] } } ] }
    assert_equal [], parser.send(:extract_transactions, fake_response2)
  end

  private

  def build_gemini_response(transactions)
    {
      "candidates" => [ {
        "content" => {
          "parts" => [ { "text" => { transactions: transactions }.to_json } ]
        }
      } ]
    }
  end

  public

  test "build_prompt includes current year" do
    parser = AiTextParser.new(api_key: "test_key")
    prompt = parser.send(:build_prompt, "test text")
    assert_includes prompt, Date.current.year.to_s
    assert_includes prompt, "test text"
  end

  test "TRANSACTION_SCHEMA has required structure" do
    schema = AiTextParser::TRANSACTION_SCHEMA
    assert_equal "OBJECT", schema[:type]
    assert schema[:properties][:transactions]
    assert_equal "ARRAY", schema[:properties][:transactions][:type]

    item_props = schema[:properties][:transactions][:items][:properties]
    assert item_props[:date]
    assert item_props[:merchant]
    assert item_props[:amount]
    assert item_props[:institution], "institution フィールドはスキーマに存在するが、optional"
    assert item_props[:payment_type]
    assert item_props[:is_cancel]
    assert item_props[:confidence]

    # institution is optional — not in required array
    required_fields = schema[:properties][:transactions][:items][:required]
    assert_not_includes required_fields, "institution", "institution は required に含まれてはいけない"
  end

  test "extract_transactions succeeds without institution field" do
    parser = AiTextParser.new(api_key: "test_key")

    fake_response = {
      "candidates" => [ {
        "content" => {
          "parts" => [ {
            "text" => {
              transactions: [
                {
                  date: "2026-03-15",
                  merchant: "스타벅스강남점",
                  amount: 5800,
                  payment_type: "lump_sum",
                  is_cancel: false,
                  confidence: 0.88
                  # institution 필드 없음
                }
              ]
            }.to_json
          } ]
        }
      } ]
    }

    transactions = parser.send(:extract_transactions, fake_response)
    assert_equal 1, transactions.size
    tx = transactions.first
    assert_equal "스타벅스강남점", tx[:merchant]
    assert_nil tx[:institution]
  end
end
