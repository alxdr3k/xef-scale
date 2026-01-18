# frozen_string_literal: true

require 'net/http'
require 'json'

class GeminiCategoryService
  # 폴백 순서대로 시도할 모델 목록
  MODELS = [
    'gemini-3-flash-preview',
    'gemini-2.5-flash-preview-09-2025',
    'gemini-2.5-flash',
    'gemini-2.5-flash-lite-preview-09-2025',
    'gemini-2.5-flash-lite'
  ].freeze

  API_BASE_URL = 'https://generativelanguage.googleapis.com/v1beta/models'

  class ApiError < StandardError; end
  class AllModelsFailedError < StandardError; end

  def initialize(api_key = nil)
    @api_key = api_key || ENV.fetch('GEMINI_API_KEY', nil)
    raise ArgumentError, 'GEMINI_API_KEY가 설정되지 않았습니다' if @api_key.blank?
  end

  # 여러 merchant에 대해 한 번에 카테고리 추천 (배치 처리)
  # @param merchants [Array<String>] 상점/내역 이름 목록
  # @param available_categories [Array<Category>] 선택 가능한 카테고리 목록
  # @return [Hash<String, String>] { merchant_name => category_name }
  def suggest_categories_batch(merchants, available_categories)
    return {} if merchants.blank?

    # 중복 제거
    unique_merchants = merchants.uniq
    Rails.logger.info "[GeminiCategoryService] Batch categorization for #{unique_merchants.size} merchants"

    prompt = build_batch_prompt(unique_merchants, available_categories)

    MODELS.each do |model|
      begin
        Rails.logger.info "[GeminiCategoryService] Trying model: #{model} for batch (#{unique_merchants.size} items)"
        response = call_gemini_api(model, prompt, max_tokens: 4096)
        results = parse_batch_response(response, unique_merchants, available_categories)

        if results.present?
          Rails.logger.info "[GeminiCategoryService] Batch success with #{model}: #{results.size} categorized"
          return results
        end
      rescue ApiError => e
        Rails.logger.warn "[GeminiCategoryService] #{model} failed: #{e.message}"
        next
      rescue StandardError => e
        Rails.logger.error "[GeminiCategoryService] Unexpected error with #{model}: #{e.message}"
        next
      end
    end

    # 모든 모델 실패 시 빈 결과 반환
    Rails.logger.warn "[GeminiCategoryService] All models failed for batch categorization"
    {}
  end

  # 단일 merchant에 대해 카테고리 추천 (하위 호환용)
  # @param merchant_name [String] 상점/내역 이름
  # @param available_categories [Array<Category>] 선택 가능한 카테고리 목록
  # @return [String] 추천된 카테고리 이름
  def suggest_category(merchant_name, available_categories)
    results = suggest_categories_batch([merchant_name], available_categories)
    results[merchant_name] || fallback_category_name(available_categories)
  end

  private

  def fallback_category_name(available_categories)
    available_categories.find { |c| c.name == '기타' }&.name || available_categories.first&.name
  end

  def build_batch_prompt(merchants, categories)
    category_list = categories.map(&:name).join(', ')
    merchant_list = merchants.each_with_index.map { |m, i| "#{i + 1}. #{m}" }.join("\n")

    <<~PROMPT
      당신은 한국어 가계부 지출 분류 전문가입니다.

      다음 상점/내역 목록을 보고 각각에 가장 적합한 카테고리를 선택해주세요.

      선택 가능한 카테고리 목록:
      #{category_list}

      분류할 상점/내역 목록:
      #{merchant_list}

      응답 규칙:
      1. 각 항목에 대해 "번호. 카테고리명" 형식으로 응답하세요
      2. 반드시 위 카테고리 목록 중 하나만 정확히 선택하세요
      3. 확실하지 않으면 "기타"를 선택하세요
      4. 다른 설명 없이 결과만 출력하세요

      응답 예시:
      1. 식비
      2. 교통/자동차
      3. 기타

      결과:
    PROMPT
  end

  def call_gemini_api(model, prompt, max_tokens: 50)
    uri = URI("#{API_BASE_URL}/#{model}:generateContent?key=#{@api_key}")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 60
    http.open_timeout = 10

    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request.body = {
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: {
        temperature: 0.1,
        maxOutputTokens: max_tokens,
        topP: 0.8
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

  def parse_batch_response(response, merchants, available_categories)
    text = response.dig('candidates', 0, 'content', 'parts', 0, 'text')&.strip
    return {} if text.blank?

    category_names = available_categories.map(&:name)
    results = {}

    # "번호. 카테고리명" 형식 파싱
    text.each_line do |line|
      line = line.strip
      next if line.blank?

      # "1. 식비" 또는 "1.식비" 형식 매칭
      if line =~ /^(\d+)\.\s*(.+)$/
        index = ::Regexp.last_match(1).to_i - 1
        category_text = ::Regexp.last_match(2).strip

        next if index < 0 || index >= merchants.size

        merchant = merchants[index]

        # 정확히 일치하는 카테고리 찾기
        matched = category_names.find { |name| category_text == name }
        matched ||= category_names.find { |name| category_text.include?(name) }

        results[merchant] = matched if matched
      end
    end

    results
  end
end
