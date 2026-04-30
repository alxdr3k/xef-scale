require "test_helper"

class GeminiVisionParserServiceTest < ActiveSupport::TestCase
  test "parse_response extracts transactions from object-shaped Gemini payload" do
    service = GeminiVisionParserService.new("test_key")

    body = {
      payment_date: "2026.01.14",
      transactions: [
        {
          date: "2026.01.05",
          merchant: "스타벅스강남점",
          amount: 5800,
          payment_type: "lump_sum"
        },
        {
          date: "2026.01.08",
          merchant: "올리브영 명동점",
          amount: 60000,
          payment_type: "installment",
          installment_month: 1,
          installment_total: 3
        }
      ]
    }

    result = service.send(:parse_response, build_gemini_response(body))

    assert_equal "2026.01.14", result[:payment_date]
    assert_equal 2, result[:transactions].size

    tx = result[:transactions].first
    assert_equal "2026.01.05", tx[:date]
    assert_equal "스타벅스강남점", tx[:merchant]
    assert_equal 5800, tx[:amount]
    assert_equal "lump_sum", tx[:payment_type]

    installment = result[:transactions].last
    assert_equal "installment", installment[:payment_type]
    assert_equal 1, installment[:installment_month]
    assert_equal 3, installment[:installment_total]
  end

  test "parse_response tolerates legacy bare-array payload" do
    service = GeminiVisionParserService.new("test_key")

    body = [
      { date: "2026.01.05", merchant: "편의점", amount: 3200, payment_type: "lump_sum" }
    ]

    result = service.send(:parse_response, build_gemini_response(body))

    assert_nil result[:payment_date]
    assert_equal 1, result[:transactions].size
    assert_equal "편의점", result[:transactions].first[:merchant]
  end

  test "parse_response returns empty result on malformed JSON" do
    service = GeminiVisionParserService.new("test_key")

    response = {
      "candidates" => [ { "content" => { "parts" => [ { "text" => "not valid json {{{" } ] } } ]
    }

    result = service.send(:parse_response, response)

    assert_nil result[:payment_date]
    assert_equal [], result[:transactions]
  end

  test "parse_response separates incomplete entries missing required fields" do
    service = GeminiVisionParserService.new("test_key")

    body = {
      payment_date: nil,
      transactions: [
        { date: "2026.01.05", merchant: "OK가게", amount: 1000 },
        { date: nil, merchant: "가맹점", amount: 1000 },
        { date: "2026.01.06", merchant: nil, amount: 1000 },
        { date: "2026.01.07", merchant: "무금액", amount: nil }
      ]
    }

    result = service.send(:parse_response, build_gemini_response(body))
    assert_equal 1, result[:transactions].size
    assert_equal "OK가게", result[:transactions].first[:merchant]
    assert_equal 3, result[:incomplete_transactions].size
    assert_equal [ "date" ], result[:incomplete_transactions].first[:missing_fields]
    assert_equal "가맹점", result[:incomplete_transactions].first[:merchant]
  end

  private

  def build_gemini_response(body)
    {
      "candidates" => [ {
        "content" => {
          "parts" => [ { "text" => body.to_json } ]
        }
      } ]
    }
  end
end
