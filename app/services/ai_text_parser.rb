# frozen_string_literal: true

# AI Text Parser — Parses Korean financial SMS/text into structured transaction data
# using Gemini Flash. Part of Phase B2.
#
# Usage:
#   parser = AiTextParser.new
#   result = parser.parse("신한체크 승인 홍*동 50,000원 일시불 03/15 14:30 스타벅스강남점")
#   # => { transactions: [...], raw_text: "...", confidence: 0.95 }
class AiTextParser
  MODELS = [
    "gemini-3-flash-preview",
    "gemini-2.5-flash-preview-09-2025",
    "gemini-2.5-flash",
    "gemini-2.5-flash-lite"
  ].freeze

  API_BASE_URL = "https://generativelanguage.googleapis.com/v1beta/models"

  class ApiError < StandardError; end
  class ParseError < StandardError; end

  def initialize(api_key: nil)
    @api_key = api_key || ENV.fetch("GEMINI_API_KEY", nil)
    raise ArgumentError, "GEMINI_API_KEY가 설정되지 않았습니다" if @api_key.blank?
  end

  # Parse raw text (SMS, copy-paste) into structured transactions
  # @param text [String] Raw financial text (one or more SMS messages)
  # @return [Hash] { transactions: [...], raw_text: String, model_used: String }
  def parse(text)
    raise ParseError, "입력 텍스트가 비어있습니다" if text.blank?

    prompt = build_prompt(text)

    MODELS.each do |model|
      begin
        Rails.logger.info "[AiTextParser] Trying model: #{model}"
        response = call_gemini_api(model, prompt)
        transactions = extract_transactions(response)

        if transactions.present?
          Rails.logger.info "[AiTextParser] Success with #{model}: #{transactions.size} transactions parsed"
          return {
            transactions: transactions,
            raw_text: text,
            model_used: model
          }
        end
      rescue ApiError => e
        Rails.logger.warn "[AiTextParser] #{model} failed: #{e.message}"
        next
      rescue StandardError => e
        Rails.logger.error "[AiTextParser] Unexpected error with #{model}: #{e.message}"
        next
      end
    end

    Rails.logger.warn "[AiTextParser] All models failed"
    { transactions: [], raw_text: text, model_used: nil }
  end

  private

  def build_prompt(text)
    current_year = Date.current.year

    <<~PROMPT
      당신은 한국 금융 문자 메시지 파싱 전문가입니다.

      아래 텍스트에서 거래 내역을 추출하세요. 텍스트는 한국 금융기관(카드사, 은행)의 승인/출금 알림 문자일 수 있습니다.

      입력 텍스트:
      #{text}

      각 거래에 대해 다음 필드를 추출하세요:
      - date: 거래 날짜 (YYYY-MM-DD 형식, 연도가 없으면 #{current_year}년 사용)
      - merchant: 가맹점/상점명
      - amount: 금액 (숫자만, 콤마 제거)
      - institution: 금융기관명 (신한카드, KB국민카드, 하나카드, 토스뱅크 등)
      - payment_type: 결제유형 (lump_sum=일시불, installment=할부)
      - installment_month: 할부인 경우 현재 회차 (일시불이면 null)
      - installment_total: 할부인 경우 총 개월수 (일시불이면 null)
      - is_cancel: 승인취소 여부 (true/false)
      - confidence: 파싱 신뢰도 (0.0~1.0)

      규칙:
      1. 금액에서 "원", 콤마를 제거하고 정수로 변환
      2. 날짜에 연도가 없으면 #{current_year}년으로 설정
      3. 승인취소/취소 문자는 is_cancel: true
      4. 텍스트에 여러 거래가 있으면 모두 추출
      5. 거래가 아닌 텍스트(광고, 안내 등)는 무시
      6. 확실하지 않은 필드는 null로 설정
    PROMPT
  end

  TRANSACTION_SCHEMA = {
    type: "OBJECT",
    properties: {
      transactions: {
        type: "ARRAY",
        items: {
          type: "OBJECT",
          properties: {
            date: { type: "STRING", description: "YYYY-MM-DD" },
            merchant: { type: "STRING" },
            amount: { type: "INTEGER" },
            institution: { type: "STRING" },
            payment_type: { type: "STRING", enum: %w[lump_sum installment] },
            installment_month: { type: "INTEGER", nullable: true },
            installment_total: { type: "INTEGER", nullable: true },
            is_cancel: { type: "BOOLEAN" },
            confidence: { type: "NUMBER" }
          },
          required: %w[date merchant amount institution payment_type is_cancel confidence]
        }
      }
    },
    required: %w[transactions]
  }.freeze

  def call_gemini_api(model, prompt)
    uri = URI("#{API_BASE_URL}/#{model}:generateContent")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 30
    http.open_timeout = 10

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["x-goog-api-key"] = @api_key
    request.body = {
      contents: [ { parts: [ { text: prompt } ] } ],
      generationConfig: {
        temperature: 0.1,
        maxOutputTokens: 4096,
        topP: 0.8,
        responseMimeType: "application/json",
        responseSchema: TRANSACTION_SCHEMA
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

  def extract_transactions(response)
    text = response.dig("candidates", 0, "content", "parts", 0, "text")
    return [] if text.blank?

    parsed = JSON.parse(text)
    transactions = parsed["transactions"] || []

    transactions.map do |tx|
      {
        date: parse_date(tx["date"]),
        merchant: tx["merchant"]&.strip,
        amount: tx["amount"].to_i,
        institution: tx["institution"]&.strip,
        payment_type: tx["payment_type"] || "lump_sum",
        installment_month: tx["installment_month"],
        installment_total: tx["installment_total"],
        is_cancel: tx["is_cancel"] || false,
        confidence: tx["confidence"]&.to_f || 0.0
      }
    end.select { |tx| tx[:date].present? && tx[:amount].positive? }
  rescue JSON::ParserError => e
    Rails.logger.error "[AiTextParser] JSON parse error: #{e.message}"
    []
  end

  def parse_date(date_str)
    return nil if date_str.blank?
    Date.parse(date_str)
  rescue Date::Error
    nil
  end
end
