require "test_helper"

class Parsers::ShinhanTextParserTest < ActiveSupport::TestCase
  test "skips OCR-garbled date-like lines in merchant section" do
    # "25. 10.13" and "25.09:30" are metadata (installment end dates), not transaction dates
    # They should NOT appear as merchant names
    raw_text = <<~TEXT
      이용일자 이용카드 이용가맹점
      25.08.06
      25. 10.13
      25.09.30
      25.09:30
      본인357
      DB손해보험
      할부 합계
      본인357
      테스트가맹점
      일시불(일반) 소계
      일시불 합계
      총합계
      이용금액
      원금
      수수료(이자)
      186,700
      186,700
      10,000
      10,000
      196,700
      이용혜택
    TEXT

    parser = Parsers::ShinhanTextParser.new(raw_text)
    results = parser.parse

    assert_equal 2, results.size

    # First transaction should be DB손해보험, not the garbled date string
    assert_equal "DB손해보험", results[0][:merchant]
    assert_equal 186_700, results[0][:amount]

    assert_equal "테스트가맹점", results[1][:merchant]
    assert_equal 10_000, results[1][:amount]
  end

  test "recognizes card pattern with OCR dot separator (본인.357)" do
    raw_text = <<~TEXT
      이용일자 이용카드 이용가맹점
      25.10.02
      25.10.02
      본인357
      버거킹 수지점
      본인.357
      롯데월드몰점
      일시불(일반) 소계
      일시불 합계
      총합계
      이용금액
      원금
      수수료(이자)
      10,000
      20,000
      30,000
      이용혜택
    TEXT

    parser = Parsers::ShinhanTextParser.new(raw_text)
    results = parser.parse

    assert_equal 2, results.size
    # Should be two separate merchants, not merged
    assert_equal "버거킹 수지점", results[0][:merchant]
    assert_equal "롯데월드몰점", results[1][:merchant]
  end

  test "cleans leading dots from merchant names" do
    raw_text = <<~TEXT
      이용일자 이용카드 이용가맹점
      25.10.05
      본인357
      . 나눌터 설렁탕
      일시불(일반) 소계
      일시불 합계
      총합계
      이용금액
      원금
      수수료(이자)
      39,000
      39,000
      이용혜택
    TEXT

    parser = Parsers::ShinhanTextParser.new(raw_text)
    results = parser.parse

    assert_equal 1, results.size
    assert_equal "나눌터 설렁탕", results[0][:merchant]
  end

  test "handles inline card with OCR dot (본인.357 가맹점)" do
    raw_text = <<~TEXT
      이용일자 이용카드 이용가맹점
      25.10.01
      본인.357 테스트식당
      일시불(일반) 소계
      일시불 합계
      총합계
      이용금액
      원금
      수수료(이자)
      15,000
      15,000
      이용혜택
    TEXT

    parser = Parsers::ShinhanTextParser.new(raw_text)
    results = parser.parse

    assert_equal 1, results.size
    assert_equal "테스트식당", results[0][:merchant]
  end
end
