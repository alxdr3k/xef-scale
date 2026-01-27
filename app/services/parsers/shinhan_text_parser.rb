module Parsers
  class ShinhanTextParser
    attr_reader :raw_text, :workspace

    DATE_PATTERN = /\d{2}\.\d{2}\.\d{2}/
    CARD_PATTERN = /^본인\d{2,4}$/
    AMOUNT_PATTERN = /^[\d,]+$/
    INSTALLMENT_PATTERN = /^(\d+)\/(\d+)$/

    # Assume dates are within this many years of current year for century detection
    CENTURY_FUTURE_THRESHOLD = 10

    # Lines to skip when looking for merchants
    SKIP_PATTERNS = [
      /합계/, /소계/, /연회비/, /이용일자/, /이용카드/, /이용가맹점/,
      /이용금액/, /할부/, /기간/, /회차/, /원금/, /수수료/, /이자/,
      /이용혜택/, /구분/, /금액/, /잔액/, /포인트/, /적립/, /무이자/,
      /^\d+건$/, /^•$/
    ].freeze

    def initialize(raw_text, workspace: nil)
      @raw_text = raw_text
      @workspace = workspace
    end

    def parse
      return [] if raw_text.blank?

      lines = raw_text.split("\n").map(&:strip).reject(&:blank?)

      # Step 1: Extract all dates in order
      dates = extract_dates(lines)
      return [] if dates.empty?

      # Step 2: Extract card + merchant pairs
      merchants_with_cards = extract_merchants(lines)

      # Step 3: Extract installment info (if any) - BEFORE amounts to know structure
      installments = extract_installments(lines)

      # Step 4: Extract amounts from "원금" section using installment info
      amounts = extract_amounts(lines, dates.size, installments.size)

      # Step 5: Match them together
      transactions = []
      dates.each_with_index do |date, i|
        # Safety check: skip if date is nil (shouldn't happen but defensive)
        next if date.nil?

        merchant_info = merchants_with_cards[i] || {}
        amount = amounts[i]

        # Skip only if amount is nil (not if it's 0, which is valid for coupons)
        next if amount.nil?

        merchant = merchant_info[:merchant]
        next if merchant.blank?

        # Determine payment type
        payment_type = determine_payment_type(
          merchant: merchant,
          installment_total: installments[i]&.dig(:total)
        )

        transactions << build_transaction(
          date: date,
          merchant: merchant,
          amount: amount,
          installment_total: installments[i]&.dig(:total),
          installment_month: installments[i]&.dig(:month),
          payment_type: payment_type
        )
      end

      transactions
    end

    private

    def extract_dates(lines)
      dates = []
      lines.each do |line|
        if line.match?(DATE_PATTERN) && line.match?(/^\d{2}\.\d{2}\.\d{2}$/)
          dates << parse_date_with_century(line)
        end
      end
      dates.compact
    end

    def extract_merchants(lines)
      merchants = []
      in_merchant_section = false
      pending_merchant_parts = []

      # New format: "본인XXX 가맹점명" or "본인XXX" followed by "가맹점명"
      card_inline_pattern = /^본인\s?\d{2,4}\s+(.+)$/

      lines.each_with_index do |line, idx|
        # Start merchant section after header line
        if line.include?("이용가맹점")
          in_merchant_section = true
          next
        end

        # End merchant section at amount headers (use flag instead of break to allow multiple sections)
        if in_merchant_section && (line.include?("이용금액") || line.include?("원금") || line.include?("이번달 내실 금액"))
          # Flush any pending merchant
          if pending_merchant_parts.any?
            merchant = pending_merchant_parts.join(" ")
            merchants << { merchant: merchant } unless merchant.blank?
            pending_merchant_parts = []
          end
          in_merchant_section = false
          next
        end

        next unless in_merchant_section

        # Skip dates
        next if line.match?(/^\d{2}\.\d{2}\.\d{2}$/)

        # Skip unwanted lines
        next if should_skip?(line)

        # Check for inline card + merchant: "본인357 DB손해보험"
        if (match = line.match(card_inline_pattern))
          # Flush previous pending merchant
          if pending_merchant_parts.any?
            merchant = pending_merchant_parts.join(" ")
            merchants << { merchant: merchant } unless merchant.blank?
            pending_merchant_parts = []
          end

          merchant_name = match[1].strip
          merchants << { merchant: merchant_name } unless merchant_name.blank?
          next
        end

        # Check for card-only line: "본인357" or "본인 425"
        if line.match?(/^본인\s?\d{2,4}$/)
          # Flush previous pending merchant
          if pending_merchant_parts.any?
            merchant = pending_merchant_parts.join(" ")
            merchants << { merchant: merchant } unless merchant.blank?
            pending_merchant_parts = []
          end
          next
        end

        # Clean and accumulate merchant name parts
        merchant_part = clean_merchant(line)
        next if merchant_part.blank?

        # Add to pending merchant parts
        pending_merchant_parts << merchant_part

        # Look ahead: if next line is a card pattern or ends section, flush
        next_line = lines[idx + 1]
        if next_line.nil? ||
           next_line.match?(/^본인\s?\d{2,4}/) ||
           next_line.include?("이용금액") ||
           next_line.include?("원금") ||
           next_line.include?("합계") ||
           next_line.include?("소계") ||
           next_line.include?("이번달")
          merchant = pending_merchant_parts.join(" ")
          merchants << { merchant: merchant } unless merchant.blank?
          pending_merchant_parts = []
        end
      end

      merchants
    end

    def extract_amounts(lines, expected_count, installment_count)
      # New data format from Shinhan Card web copy:
      # After "수수료(이자)" header, amounts are listed vertically (not in pairs)
      #
      # Pattern:
      #   원금
      #   수수료(이자)
      #   186,700    <- installment principal
      #   186,700    <- installment subtotal (same as above for 1 installment)
      #   11,000     <- lump sum 1
      #   11,000     <- subtotal (same as above for 1 transaction)
      #   50,000     <- lump sum 2
      #   50,000     <- lump sum 3
      #   100,000    <- subtotal (50000 + 50000)
      #   111,000    <- grand subtotal (11000 + 100000)
      #   ...
      #
      # Strategy:
      # 1. Collect all amounts after "수수료" header
      # 2. Skip subtotals (values that equal sum of recent collected amounts)
      # 3. Return first N amounts that are actual transactions

      all_amounts = []
      in_amount_section = false

      lines.each do |line|
        # Start after 원금 header (new format) or 수수료 header (old format)
        if line == "원금" || line.include?("수수료(이자)")
          in_amount_section = true
          next
        end

        # Stop at 수수료 section (if we started at 원금) or benefit section
        if in_amount_section
          # If we see 수수료 after starting from 원금, stop
          if line.include?("수수료")
            break
          end
          # Stop at benefit section
          if line.include?("이용혜택") || line.include?("구분") || line.include?("결제 후")
            break
          end
        end

        next unless in_amount_section

        if line.match?(AMOUNT_PATTERN)
          amount = line.gsub(",", "").to_i
          all_amounts << amount
        end
      end

      # Now filter out subtotals
      # Key insight: when current == previous, check if next == current + previous
      # If yes, both are transactions. If no, current is a subtotal.
      result = []
      i = 0

      while i < all_amounts.length && result.size < expected_count
        current = all_amounts[i]
        next_val = all_amounts[i + 1]
        after_next = all_amounts[i + 2]

        # Check if current equals sum of all collected so far (grand total)
        if result.any? && current == result.sum
          i += 1
          next
        end

        # Check if current equals sum of lump_sum transactions
        lump_sum_result = result[installment_count..]
        if lump_sum_result && lump_sum_result.any? && current == lump_sum_result.sum
          i += 1
          next
        end

        # Case: current == next (could be 2 same-amount transactions OR transaction + subtotal)
        if next_val == current
          # Check if after_next == current + next → both are transactions
          if after_next && after_next == current + next_val
            result << current
            if result.size < expected_count
              result << next_val
            end
            i += 3  # Skip current, next, and the subtotal (after_next)
            next
          else
            # Only current is transaction, next is subtotal
            result << current
            i += 2  # Skip current and subtotal
            next
          end
        end

        # Normal case: add current as transaction
        result << current
        i += 1
      end

      result.first(expected_count)
    end

    def extract_installments(lines)
      installments = []

      lines.each do |line|
        if line.match?(INSTALLMENT_PATTERN)
          match = line.match(INSTALLMENT_PATTERN)
          installments << {
            total: match[1].to_i,   # 기간
            month: match[2].to_i    # 회차
          }
        end
      end

      # Pad with nils to match transaction count
      installments
    end

    def should_skip?(line)
      SKIP_PATTERNS.any? { |pattern| line.match?(pattern) }
    end

    def clean_merchant(name)
      name = name.sub(/^[•·]\s*/, "")  # Remove bullet points
      name = name.sub(/^본인\d+\s*/, "")  # Remove card prefix if inline
      name.strip
    end

    def parse_date_with_century(date_str)
      yy, mm, dd = date_str.split(".").map(&:to_i)
      current_century_threshold = (Time.current.year % 100) + CENTURY_FUTURE_THRESHOLD
      century = yy > current_century_threshold ? 1900 : 2000
      date = Date.new(century + yy, mm, dd)

      # Reject dates outside reasonable transaction window (5 years past to 1 year future)
      return nil if date < 5.years.ago.to_date || date > 1.year.from_now.to_date

      date
    rescue ArgumentError
      nil
    end

    def determine_payment_type(merchant:, installment_total:)
      # Check for coupon first
      return "coupon" if merchant.include?("소비쿠폰")

      # Check for installment
      return "installment" if installment_total && installment_total > 1

      # Default to lump sum
      "lump_sum"
    end

    def build_transaction(date:, merchant:, amount:, installment_total: nil, installment_month: nil, payment_type: "lump_sum")
      {
        date: date,
        merchant: merchant,
        description: nil,
        amount: amount,
        institution_identifier: "shinhan_card",
        installment_total: installment_total,
        installment_month: installment_month,
        payment_type: payment_type
      }
    end
  end
end
