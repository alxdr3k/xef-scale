# frozen_string_literal: true

require "net/http"
require "json"
require "base64"

class GeminiVisionParserService
  MODELS = [
    "gemini-2.5-flash"
  ].freeze

  API_BASE_URL = "https://generativelanguage.googleapis.com/v1beta/models"

  class ApiError < StandardError; end
  class AllModelsFailedError < StandardError; end

  EMPTY_RESULT = { payment_date: nil, transactions: [], incomplete_transactions: [] }.freeze

  RESPONSE_SCHEMA = {
    type: "OBJECT",
    properties: {
      payment_date: { type: "STRING", description: "결제일 (YYYY.MM.DD 형식, 명세서 첫 페이지의 '결제일' 항목)" },
      transactions: {
        type: "ARRAY",
        items: {
          type: "OBJECT",
          properties: {
            date: { type: "STRING", description: "거래 날짜 (YYYY.MM.DD 형식)" },
            merchant: { type: "STRING", description: "가맹점명" },
            amount: { type: "INTEGER", description: "이번달 내실 금액 (원금)" },
            payment_type: { type: "STRING", enum: %w[lump_sum installment coupon], description: "일시불/할부/소비쿠폰" },
            installment_month: { type: "INTEGER", description: "할부 현재 회차 (할부인 경우만)" },
            installment_total: { type: "INTEGER", description: "할부 총 기간 (할부인 경우만)" }
          }
        }
      }
    },
    required: %w[transactions]
  }.freeze

  PROMPT = <<~PROMPT
    이 이미지는 신한카드 이용대금 명세서입니다.
    명세서에서 결제일과 각 거래 내역을 추출해주세요.

    추출 규칙:
    0. payment_date: 명세서 첫 페이지에서 '결제일' 항목을 찾아 YYYY.MM.DD 형식으로 변환 (예: 26.01.14 → 2026.01.14)
    1. date: 이용일자를 YYYY.MM.DD 형식으로 변환 (예: 25.08.06 → 2025.08.06)
    2. merchant: 가맹점명 (이용가맹점 열)
    3. amount:
       - 일반 거래(일시불/할부): "이번달 내실 금액" 또는 "원금" 열의 금액
       - 소비쿠폰: "이용금액" 열의 금액 (원금이 0이어도 이용금액 사용)
    4. payment_type: "일시불" → "lump_sum", "할부" → "installment", "소비쿠폰" → "coupon"
    5. installment_month: 할부인 경우 "기간/회차" 열에서 현재 회차 (예: "3/12" → 3)
    6. installment_total: 할부인 경우 총 기간 (예: "3/12" → 12)
    7. 합계, 소계 행은 제외
    8. 날짜, 가맹점, 금액 중 일부가 화면에 보이지 않는 거래도 버리지 말고 보이는 필드만 채워주세요.
       - 같은 날짜 그룹 안에 있음이 화면에서 명확할 때만 date를 채웁니다.
       - 날짜 헤더가 잘려 보이지 않거나 추정해야 하면 date는 비워둡니다.
       - 금액이나 가맹점이 보이지 않으면 해당 필드도 비워둡니다.

    모든 거래를 빠짐없이 추출해주세요.
  PROMPT

  def initialize(api_key = nil)
    @api_key = api_key || ENV.fetch("GEMINI_API_KEY", nil)
    raise ArgumentError, "GEMINI_API_KEY가 설정되지 않았습니다" if @api_key.blank?
  end

  # @param tempfile [Tempfile] 이미지 파일
  # @param mime_type [String] 이미지 MIME 타입
  # @return [Hash] { payment_date: String or nil, transactions: Array<Hash> }
  def parse_image(tempfile, mime_type:)
    image_data = Base64.strict_encode64(File.binread(tempfile.path))

    MODELS.each do |model|
      begin
        Rails.logger.info "[GeminiVisionParser] Trying model: #{model}"
        response = call_gemini_api(model, image_data, mime_type)
        result = parse_response(response)

        if result[:transactions].present? || result[:incomplete_transactions].present?
          Rails.logger.info "[GeminiVisionParser] Success with #{model}: #{result[:transactions].size} complete, #{result[:incomplete_transactions].size} incomplete transactions"
          return result
        end
      rescue ApiError => e
        Rails.logger.warn "[GeminiVisionParser] #{model} failed: #{e.message}"
        next
      rescue StandardError => e
        Rails.logger.error "[GeminiVisionParser] Unexpected error with #{model}: #{e.message}"
        next
      end
    end

    Rails.logger.warn "[GeminiVisionParser] All models failed"
    raise AllModelsFailedError, "모든 Gemini 모델에서 이미지 파싱에 실패했습니다"
  end

  private

  def call_gemini_api(model, image_data, mime_type)
    uri = URI("#{API_BASE_URL}/#{model}:generateContent")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 120
    http.open_timeout = 10

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["x-goog-api-key"] = @api_key
    request.body = {
      contents: [
        {
          parts: [
            { inline_data: { mime_type: mime_type, data: image_data } },
            { text: PROMPT }
          ]
        }
      ],
      generationConfig: {
        temperature: 0.1,
        responseMimeType: "application/json",
        responseSchema: RESPONSE_SCHEMA
      }
    }.to_json

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      error_body = begin
        JSON.parse(response.body)
      rescue StandardError
        response.body
      end
      raise ApiError, "HTTP #{response.code}: #{error_body}"
    end

    JSON.parse(response.body)
  end

  def parse_response(response)
    text = response.dig("candidates", 0, "content", "parts", 0, "text")
    return EMPTY_RESULT.dup if text.blank?

    data = JSON.parse(text)

    # The response schema is an OBJECT { payment_date, transactions: [...] }.
    # Tolerate legacy/bare-array responses as well.
    raw_transactions = if data.is_a?(Hash)
      data["transactions"] || []
    elsif data.is_a?(Array)
      data
    else
      []
    end

    transactions = []
    incomplete_transactions = []

    raw_transactions.each do |item|
      next unless item.is_a?(Hash)

      normalized = {
        date: item["date"],
        merchant: item["merchant"].to_s.strip.presence,
        amount: item["amount"].present? ? item["amount"].to_i.abs : nil,
        payment_type: item["payment_type"] || "lump_sum",
        installment_month: item["installment_month"]&.to_i,
        installment_total: item["installment_total"]&.to_i
      }

      missing_fields = missing_transaction_fields(normalized)
      if missing_fields.empty?
        transactions << normalized
      elsif salvageable_incomplete_transaction?(normalized)
        incomplete_transactions << normalized.merge(missing_fields: missing_fields)
      end
    end

    payment_date = data.is_a?(Hash) ? data["payment_date"] : nil

    { payment_date: payment_date, transactions: transactions, incomplete_transactions: incomplete_transactions }
  rescue JSON::ParserError => e
    Rails.logger.error "[GeminiVisionParser] JSON parse error: #{e.message}"
    EMPTY_RESULT.dup
  end

  def missing_transaction_fields(item)
    [].tap do |fields|
      fields << "date" if item[:date].blank?
      fields << "merchant" if item[:merchant].blank?
      fields << "amount" if item[:amount].blank? || item[:amount].zero?
    end
  end

  def salvageable_incomplete_transaction?(item)
    item[:merchant].present? || item[:amount].present?
  end
end
