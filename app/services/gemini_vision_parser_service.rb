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
          },
          required: %w[date merchant amount payment_type]
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

        if result[:transactions].present?
          Rails.logger.info "[GeminiVisionParser] Success with #{model}: #{result[:transactions].size} transactions"
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
    uri = URI("#{API_BASE_URL}/#{model}:generateContent?key=#{@api_key}")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 120
    http.open_timeout = 10

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
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
    return [] if text.blank?

    data = JSON.parse(text)
    return [] unless data.is_a?(Array)

    data.filter_map do |item|
      next unless item["date"].present? && item["merchant"].present? && item["amount"].present?

      {
        date: item["date"],
        merchant: item["merchant"].strip,
        amount: item["amount"].to_i.abs,
        payment_type: item["payment_type"] || "lump_sum",
        installment_month: item["installment_month"]&.to_i,
        installment_total: item["installment_total"]&.to_i
      }
    end
  rescue JSON::ParserError => e
    Rails.logger.error "[GeminiVisionParser] JSON parse error: #{e.message}"
    []
  end
end
