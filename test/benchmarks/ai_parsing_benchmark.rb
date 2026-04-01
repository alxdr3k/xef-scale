# frozen_string_literal: true

# =============================================================================
# B0 Benchmark: AI Text Parsing Accuracy for Korean Financial SMS
# =============================================================================
#
# Measures AiTextParser (Gemini) accuracy against 25 synthetic Korean financial
# SMS messages covering major card companies and banks.
#
# Usage:
#   GEMINI_API_KEY=xxx rails runner test/benchmarks/ai_parsing_benchmark.rb
#
# Thresholds:
#   - Go:     >= 90% overall accuracy
#   - Target: >= 95% overall accuracy

require "json"

class AiParsingBenchmark
  CURRENT_YEAR = Date.current.year

  # Fields we score
  SCORED_FIELDS = %i[date merchant amount institution payment_type is_cancel].freeze

  # ---------------------------------------------------------------------------
  # Test Corpus — 25 Korean financial SMS samples with expected outputs
  # ---------------------------------------------------------------------------
  SAMPLES = [
    # 1. 신한체크 일시불
    {
      id: 1,
      label: "신한체크 일시불 승인",
      sms: "[Web발신]\n신한체크 승인 홍*동\n50,000원 일시불\n03/15 14:30 스타벅스강남점\n누적 1,250,000원",
      expected: {
        date: Date.new(CURRENT_YEAR, 3, 15),
        merchant: "스타벅스강남점",
        amount: 50_000,
        institution: "신한카드",
        payment_type: "lump_sum",
        is_cancel: false
      }
    },

    # 2. KB국민카드 일시불
    {
      id: 2,
      label: "KB국민카드 일시불 승인",
      sms: "[Web발신]\nKB국민카드 승인\n김*수 30,000원 일시불\n03/16 12:00 이마트 역삼점\n잔여한도 4,970,000원",
      expected: {
        date: Date.new(CURRENT_YEAR, 3, 16),
        merchant: "이마트 역삼점",
        amount: 30_000,
        institution: "KB국민카드",
        payment_type: "lump_sum",
        is_cancel: false
      }
    },

    # 3. 하나카드 할부
    {
      id: 3,
      label: "하나카드 3개월 할부",
      sms: "[Web발신]\n하나카드승인 박*영\n25,000원 3개월\n03/17 18:45 올리브영 명동점\n누적 800,000원",
      expected: {
        date: Date.new(CURRENT_YEAR, 3, 17),
        merchant: "올리브영 명동점",
        amount: 25_000,
        institution: "하나카드",
        payment_type: "installment",
        is_cancel: false
      }
    },

    # 4. 토스뱅크 출금
    {
      id: 4,
      label: "토스뱅크 출금",
      sms: "[토스뱅크] 출금 100,000원\n잔액 2,500,000원\n03/18 09:00 카카오페이",
      expected: {
        date: Date.new(CURRENT_YEAR, 3, 18),
        merchant: "카카오페이",
        amount: 100_000,
        institution: "토스뱅크",
        payment_type: "lump_sum",
        is_cancel: false
      }
    },

    # 5. 신한체크 승인취소
    {
      id: 5,
      label: "신한체크 승인취소",
      sms: "[Web발신]\n신한체크 승인취소 홍*동\n50,000원\n03/15 14:35 스타벅스강남점",
      expected: {
        date: Date.new(CURRENT_YEAR, 3, 15),
        merchant: "스타벅스강남점",
        amount: 50_000,
        institution: "신한카드",
        payment_type: "lump_sum",
        is_cancel: true
      }
    },

    # 6. 카카오뱅크 출금
    {
      id: 6,
      label: "카카오뱅크 출금 (가맹점 없음)",
      sms: "[카카오뱅크] 출금 35,000원\n잔액 1,200,000원\n이름없음\n03/19 20:15",
      expected: {
        date: Date.new(CURRENT_YEAR, 3, 19),
        merchant: "이름없음",
        amount: 35_000,
        institution: "카카오뱅크",
        payment_type: "lump_sum",
        is_cancel: false
      }
    },

    # 7. 삼성카드 일시불
    {
      id: 7,
      label: "삼성카드 일시불 승인",
      sms: "[Web발신]\n삼성카드 승인\n이*호 42,000원 일시불\n03/20 19:30 배달의민족\n누적 2,100,000원",
      expected: {
        date: Date.new(CURRENT_YEAR, 3, 20),
        merchant: "배달의민족",
        amount: 42_000,
        institution: "삼성카드",
        payment_type: "lump_sum",
        is_cancel: false
      }
    },

    # 8. 우리카드 일시불
    {
      id: 8,
      label: "우리카드 일시불 승인",
      sms: "[Web발신]\n우리카드 승인\n최*진 18,500원 일시불\n03/21 08:15 세븐일레븐 강남역점",
      expected: {
        date: Date.new(CURRENT_YEAR, 3, 21),
        merchant: "세븐일레븐 강남역점",
        amount: 18_500,
        institution: "우리카드",
        payment_type: "lump_sum",
        is_cancel: false
      }
    },

    # 9. 현대카드 할부
    {
      id: 9,
      label: "현대카드 6개월 할부",
      sms: "[Web발신]\n현대카드 승인\n정*아 156,000원 6개월\n03/22 15:00 쿠팡\n누적 3,500,000원",
      expected: {
        date: Date.new(CURRENT_YEAR, 3, 22),
        merchant: "쿠팡",
        amount: 156_000,
        institution: "현대카드",
        payment_type: "installment",
        is_cancel: false
      }
    },

    # 10. 롯데카드 일시불
    {
      id: 10,
      label: "롯데카드 일시불 승인",
      sms: "[Web발신]\n롯데카드 승인\n한*민 9,900원 일시불\n03/23 11:00 스타벅스 을지로점",
      expected: {
        date: Date.new(CURRENT_YEAR, 3, 23),
        merchant: "스타벅스 을지로점",
        amount: 9_900,
        institution: "롯데카드",
        payment_type: "lump_sum",
        is_cancel: false
      }
    },

    # 11. NH농협카드 일시불
    {
      id: 11,
      label: "NH농협카드 일시불 승인",
      sms: "[Web발신]\nNH농협카드 승인\n강*우 55,000원 일시불\n03/24 13:30 홈플러스 수원점",
      expected: {
        date: Date.new(CURRENT_YEAR, 3, 24),
        merchant: "홈플러스 수원점",
        amount: 55_000,
        institution: "NH농협카드",
        payment_type: "lump_sum",
        is_cancel: false
      }
    },

    # 12. 신한체크 ATM 출금
    {
      id: 12,
      label: "신한체크 ATM 출금",
      sms: "[Web발신]\n신한체크 출금 홍*동\n120,000원\n03/25 10:00 ATM출금\n잔액 3,800,000원",
      expected: {
        date: Date.new(CURRENT_YEAR, 3, 25),
        merchant: "ATM출금",
        amount: 120_000,
        institution: "신한카드",
        payment_type: "lump_sum",
        is_cancel: false
      }
    },

    # 13. KB국민카드 할부
    {
      id: 13,
      label: "KB국민카드 12개월 할부",
      sms: "[Web발신]\nKB국민카드 승인\n김*수 1,200,000원 12개월\n03/26 16:00 삼성전자 강남점\n잔여한도 3,800,000원",
      expected: {
        date: Date.new(CURRENT_YEAR, 3, 26),
        merchant: "삼성전자 강남점",
        amount: 1_200_000,
        institution: "KB국민카드",
        payment_type: "installment",
        is_cancel: false
      }
    },

    # 14. 삼성카드 승인취소
    {
      id: 14,
      label: "삼성카드 승인취소",
      sms: "[Web발신]\n삼성카드 승인취소\n이*호 42,000원\n03/20 20:00 배달의민족",
      expected: {
        date: Date.new(CURRENT_YEAR, 3, 20),
        merchant: "배달의민족",
        amount: 42_000,
        institution: "삼성카드",
        payment_type: "lump_sum",
        is_cancel: true
      }
    },

    # 15. 토스뱅크 이체
    {
      id: 15,
      label: "토스뱅크 이체",
      sms: "[토스뱅크] 출금 500,000원\n잔액 1,000,000원\n03/27 14:00 김철수",
      expected: {
        date: Date.new(CURRENT_YEAR, 3, 27),
        merchant: "김철수",
        amount: 500_000,
        institution: "토스뱅크",
        payment_type: "lump_sum",
        is_cancel: false
      }
    },

    # 16. 현대카드 일시불 소액
    {
      id: 16,
      label: "현대카드 일시불 소액결제",
      sms: "[Web발신]\n현대카드 승인\n정*아 3,500원 일시불\n03/28 07:30 CU 역삼역점\n누적 3,503,500원",
      expected: {
        date: Date.new(CURRENT_YEAR, 3, 28),
        merchant: "CU 역삼역점",
        amount: 3_500,
        institution: "현대카드",
        payment_type: "lump_sum",
        is_cancel: false
      }
    },

    # 17. 카카오뱅크 이체
    {
      id: 17,
      label: "카카오뱅크 이체",
      sms: "[카카오뱅크] 출금 250,000원\n잔액 950,000원\n박영희\n03/29 11:30",
      expected: {
        date: Date.new(CURRENT_YEAR, 3, 29),
        merchant: "박영희",
        amount: 250_000,
        institution: "카카오뱅크",
        payment_type: "lump_sum",
        is_cancel: false
      }
    },

    # 18. 하나카드 승인취소
    {
      id: 18,
      label: "하나카드 승인취소",
      sms: "[Web발신]\n하나카드취소 박*영\n25,000원\n03/17 19:00 올리브영 명동점",
      expected: {
        date: Date.new(CURRENT_YEAR, 3, 17),
        merchant: "올리브영 명동점",
        amount: 25_000,
        institution: "하나카드",
        payment_type: "lump_sum",
        is_cancel: true
      }
    },

    # 19. 우리카드 할부
    {
      id: 19,
      label: "우리카드 2개월 할부",
      sms: "[Web발신]\n우리카드 승인\n최*진 89,000원 2개월\n03/30 14:20 무신사스토어",
      expected: {
        date: Date.new(CURRENT_YEAR, 3, 30),
        merchant: "무신사스토어",
        amount: 89_000,
        institution: "우리카드",
        payment_type: "installment",
        is_cancel: false
      }
    },

    # 20. 롯데카드 해외결제
    {
      id: 20,
      label: "롯데카드 해외결제",
      sms: "[Web발신]\n롯데카드 승인\n한*민 75,300원 일시불\n03/31 22:00 AMAZON.COM\n누적 2,200,000원",
      expected: {
        date: Date.new(CURRENT_YEAR, 3, 31),
        merchant: "AMAZON.COM",
        amount: 75_300,
        institution: "롯데카드",
        payment_type: "lump_sum",
        is_cancel: false
      }
    },

    # 21. NH농협카드 승인취소
    {
      id: 21,
      label: "NH농협카드 승인취소",
      sms: "[Web발신]\nNH농협카드 승인취소\n강*우 55,000원\n03/24 14:00 홈플러스 수원점",
      expected: {
        date: Date.new(CURRENT_YEAR, 3, 24),
        merchant: "홈플러스 수원점",
        amount: 55_000,
        institution: "NH농협카드",
        payment_type: "lump_sum",
        is_cancel: true
      }
    },

    # 22. 신한카드(신용) 일시불
    {
      id: 22,
      label: "신한카드 신용카드 일시불",
      sms: "[Web발신]\n신한카드 승인 홍*동\n320,000원 일시불\n04/01 09:15 대한항공\n누적 1,570,000원",
      expected: {
        date: Date.new(CURRENT_YEAR, 4, 1),
        merchant: "대한항공",
        amount: 320_000,
        institution: "신한카드",
        payment_type: "lump_sum",
        is_cancel: false
      }
    },

    # 23. KB국민카드 승인취소
    {
      id: 23,
      label: "KB국민카드 승인취소",
      sms: "[Web발신]\nKB국민카드 승인취소\n김*수 30,000원\n03/16 12:30 이마트 역삼점",
      expected: {
        date: Date.new(CURRENT_YEAR, 3, 16),
        merchant: "이마트 역삼점",
        amount: 30_000,
        institution: "KB국민카드",
        payment_type: "lump_sum",
        is_cancel: true
      }
    },

    # 24. 삼성카드 할부
    {
      id: 24,
      label: "삼성카드 10개월 할부",
      sms: "[Web발신]\n삼성카드 승인\n이*호 890,000원 10개월\n04/02 17:45 하이마트 논현점\n누적 2,990,000원",
      expected: {
        date: Date.new(CURRENT_YEAR, 4, 2),
        merchant: "하이마트 논현점",
        amount: 890_000,
        institution: "삼성카드",
        payment_type: "installment",
        is_cancel: false
      }
    },

    # 25. 토스뱅크 소액 출금
    {
      id: 25,
      label: "토스뱅크 소액 출금",
      sms: "[토스뱅크] 출금 4,500원\n잔액 995,500원\n04/03 08:00 GS25 역삼점",
      expected: {
        date: Date.new(CURRENT_YEAR, 4, 3),
        merchant: "GS25 역삼점",
        amount: 4_500,
        institution: "토스뱅크",
        payment_type: "lump_sum",
        is_cancel: false
      }
    }
  ].freeze

  # ---------------------------------------------------------------------------
  # Runner
  # ---------------------------------------------------------------------------

  def run
    puts banner
    parser = AiTextParser.new

    results = SAMPLES.map do |sample|
      print "  [#{sample[:id].to_s.rjust(2)}] #{sample[:label].ljust(32)} "
      result = parse_sample(parser, sample)
      print_inline_result(result)
      sleep 0.5 # basic rate-limit courtesy
      result
    end

    puts ""
    print_results_table(results)
    print_field_accuracy(results)
    print_summary(results)
  end

  private

  # Parse a single sample and compare against expected values
  def parse_sample(parser, sample)
    response = parser.parse(sample[:sms])
    tx = response[:transactions]&.first

    if tx.nil?
      return {
        id: sample[:id],
        label: sample[:label],
        model: response[:model_used],
        fields: SCORED_FIELDS.to_h { |f| [ f, { expected: sample[:expected][f], actual: nil, pass: false } ] },
        parsed: false
      }
    end

    fields = SCORED_FIELDS.to_h do |field|
      expected = sample[:expected][field]
      actual = tx[field]
      pass = field_match?(field, expected, actual)
      [ field, { expected: expected, actual: actual, pass: pass } ]
    end

    {
      id: sample[:id],
      label: sample[:label],
      model: response[:model_used],
      fields: fields,
      parsed: true
    }
  end

  # Compare a single field with tolerance
  def field_match?(field, expected, actual)
    return false if actual.nil? && !expected.nil?

    case field
    when :date
      expected == actual
    when :merchant
      # Allow minor variations: strip whitespace, case-insensitive substring
      return false if actual.nil?
      normalize(expected) == normalize(actual) ||
        normalize(actual).include?(normalize(expected)) ||
        normalize(expected).include?(normalize(actual))
    when :amount
      expected.to_i == actual.to_i
    when :institution
      # Allow partial matches (e.g. "신한" matches "신한카드", "신한체크")
      return false if actual.nil?
      normalize(expected) == normalize(actual) ||
        normalize(actual).include?(normalize(expected)) ||
        normalize(expected).include?(normalize(actual))
    when :payment_type
      expected.to_s == actual.to_s
    when :is_cancel
      expected == actual
    else
      expected == actual
    end
  end

  def normalize(str)
    str.to_s.strip.gsub(/\s+/, "").downcase
  end

  # ---------------------------------------------------------------------------
  # Output formatting
  # ---------------------------------------------------------------------------

  def banner
    <<~BANNER

      ================================================================
        B0 Benchmark: AI Text Parsing Accuracy
        Korean Financial SMS -> Structured Transaction Data
        #{SAMPLES.size} samples | #{SCORED_FIELDS.size} fields scored
      ================================================================

    BANNER
  end

  def print_inline_result(result)
    if !result[:parsed]
      puts "FAIL (no transaction parsed)"
      return
    end

    passes = result[:fields].values.count { |v| v[:pass] }
    total = result[:fields].size
    status = passes == total ? "PASS" : "PARTIAL #{passes}/#{total}"
    failed = result[:fields].select { |_, v| !v[:pass] }.keys
    suffix = failed.any? ? " [miss: #{failed.join(', ')}]" : ""
    puts "#{status}#{suffix}"
  end

  def print_results_table(results)
    puts "=" * 110
    header = "| #{'ID'.rjust(3)} | #{'Label'.ljust(32)} "
    SCORED_FIELDS.each { |f| header += "| #{f.to_s.center(14)} " }
    header += "|"
    puts header
    puts "-" * 110

    results.each do |r|
      row = "| #{r[:id].to_s.rjust(3)} | #{r[:label].ljust(32)} "
      r[:fields].each_value do |v|
        mark = v[:pass] ? "PASS" : "FAIL"
        row += "| #{mark.center(14)} "
      end
      row += "|"
      puts row
    end
    puts "=" * 110
    puts ""
  end

  def print_field_accuracy(results)
    puts "--- Per-Field Accuracy ---"
    total = results.size

    SCORED_FIELDS.each do |field|
      passes = results.count { |r| r[:fields][field][:pass] }
      pct = (passes.to_f / total * 100).round(1)
      bar = "#" * (pct / 2).to_i
      puts "  #{field.to_s.ljust(16)} #{passes}/#{total}  #{pct}%  #{bar}"
    end

    puts ""

    # Print mismatches detail
    any_fail = false
    results.each do |r|
      r[:fields].each do |field, v|
        next if v[:pass]
        unless any_fail
          puts "--- Mismatches Detail ---"
          any_fail = true
        end
        puts "  [#{r[:id]}] #{r[:label]} | #{field}: expected=#{v[:expected].inspect} actual=#{v[:actual].inspect}"
      end
    end
    puts "" if any_fail
  end

  def print_summary(results)
    total_fields = results.size * SCORED_FIELDS.size
    total_passes = results.sum { |r| r[:fields].values.count { |v| v[:pass] } }
    overall_pct = (total_passes.to_f / total_fields * 100).round(1)

    parsed_count = results.count { |r| r[:parsed] }
    perfect_count = results.count { |r| r[:fields].values.all? { |v| v[:pass] } }

    models_used = results.map { |r| r[:model] }.compact.tally

    puts "=" * 60
    puts "  SUMMARY"
    puts "=" * 60
    puts "  Samples:          #{results.size}"
    puts "  Parsed:           #{parsed_count}/#{results.size} (#{(parsed_count.to_f / results.size * 100).round(1)}%)"
    puts "  Perfect:          #{perfect_count}/#{results.size} (#{(perfect_count.to_f / results.size * 100).round(1)}%)"
    puts "  Overall Accuracy: #{total_passes}/#{total_fields} (#{overall_pct}%)"
    puts ""
    puts "  Models used:"
    models_used.each { |m, c| puts "    #{m}: #{c} samples" }
    puts ""

    if overall_pct >= 95.0
      puts "  Status: GO (TARGET MET) -- #{overall_pct}% >= 95%"
    elsif overall_pct >= 90.0
      puts "  Status: GO -- #{overall_pct}% >= 90% (target: 95%)"
    else
      puts "  Status: NO-GO -- #{overall_pct}% < 90%"
    end
    puts "=" * 60
    puts ""
  end
end

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
AiParsingBenchmark.new.run
