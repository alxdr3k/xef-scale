# 파서 시스템

xef-scale의 파서 시스템은 다양한 한국 금융기관의 명세서 파일을 파싱합니다.

## Why Content-Based 라우팅?

**문제**: 파일명만으로는 금융기관을 식별할 수 없습니다.
- 사용자가 파일명을 변경할 수 있음
- 동일 기관도 다양한 파일명 사용
- 다운로드 시점마다 파일명이 달라짐

**해결**: 파일 내용(헤더, 키워드)을 분석하여 기관을 식별합니다.

## ParserRouter

```ruby
# app/services/parser_router.rb

SIGNATURES = {
  toss_bank:    ["토스뱅크", "Toss", "수신자", "거래유형"],
  kakao_bank:   ["kakao", "카카오뱅크", "거래일시", "거래구분"],
  shinhan_card: ["신한카드", "이용일자", "승인번호"],
  hana_card:    ["하나카드", "이용일", "가맹점명", "이용대금 명세서"]
}

def route(processed_file)
  content = read_file_content(processed_file)  # 첫 10행/2000자
  institution = identify_institution(content)   # 시그니처 매칭

  case institution
  when :toss_bank    then Parsers::TossBankParser.new(processed_file)
  when :kakao_bank   then Parsers::KakaoBankParser.new(processed_file)
  when :shinhan_card then Parsers::ShinhanCardParser.new(processed_file)
  when :hana_card    then Parsers::HanaCardParser.new(processed_file)
  else nil  # 미지원 기관
  end
end
```

## BaseParser 상속 구조

```
BaseParser (추상 클래스)
    │
    ├── TossBankParser    (Excel, CSV)
    ├── KakaoBankParser   (Excel, CSV)
    ├── ShinhanCardParser (PDF, Excel)
    └── HanaCardParser    (Excel)
```

### BaseParser 핵심 메서드

```ruby
# app/services/parsers/base_parser.rb

def initialize(processed_file)  # 생성자
def parse                       # 구현 필수 (추상)
def institution_identifier      # 구현 필수 (반환: "toss_bank" 등)

# 유틸리티
def download_file               # ActiveStorage → 임시파일
def open_spreadsheet(tempfile)  # Roo 라이브러리로 스프레드시트 열기
def parse_date(date_string)     # 8가지 날짜 형식 파싱
def parse_amount(amount_string) # 금액 파싱 (쉼표, 통화 제거)
def build_transaction(...)      # 거래 객체 생성
```

## 기관별 파서

| 파서 | 파일 | 지원 형식 | 특이사항 |
|------|------|----------|----------|
| TossBankParser | `toss_bank_parser.rb` | Excel, CSV | 헤더행 자동 감지, outgoing/incoming 구분 |
| KakaoBankParser | `kakao_bank_parser.rb` | Excel, CSV | 거래유형 필터링 (입금 제외) |
| ShinhanCardParser | `shinhan_card_parser.rb` | PDF, Excel | PDF 텍스트 추출, "본인357" 접두사 제거 |
| HanaCardParser | `hana_card_parser.rb` | Excel | 거래일자 헤더 탐색 |

## Why Python 백업 파서?

**문제**: Ruby의 `roo` gem은 구형 `.xls` 파일(BIFF5/BIFF8) 파싱에 한계가 있습니다.

```ruby
# app/services/python_excel_parser.rb

# 일부 카카오뱅크 파일이 roo로 열리지 않을 때
# Python pandas + xlrd로 백업 처리
```

## 새 파서 추가 방법

1. `app/services/parsers/`에 새 파서 클래스 생성
2. `BaseParser` 상속
3. `parse`와 `institution_identifier` 구현
4. `ParserRouter::SIGNATURES`에 시그니처 추가
5. `ParserRouter#route`에 case 분기 추가

```ruby
# 예시: 우리카드 파서 추가

# 1. app/services/parsers/woori_card_parser.rb
class Parsers::WooriCardParser < Parsers::BaseParser
  def parse
    # Excel/PDF 파싱 로직
  end

  def institution_identifier
    "woori_card"
  end
end

# 2. parser_router.rb 수정
SIGNATURES = {
  # ...
  woori_card: ["우리카드", "이용일자", "승인번호"]
}

def route(processed_file)
  # ...
  when :woori_card then Parsers::WooriCardParser.new(processed_file)
end
```

## 지원 금융기관

| 기관 | identifier | 타입 | 비고 |
|------|-----------|------|------|
| 신한카드 | `shinhan_card` | card | PDF 지원 |
| 하나카드 | `hana_card` | card | |
| 토스뱅크 | `toss_bank` | bank | |
| 토스페이 | `toss_pay` | pay | |
| 카카오뱅크 | `kakao_bank` | bank | |
| 카카오페이 | `kakao_pay` | pay | |

## 구현 위치

| 파일 | 역할 |
|------|------|
| `app/services/parser_router.rb` | 기관 식별 및 라우팅 (110줄) |
| `app/services/parsers/base_parser.rb` | 추상 기본 클래스 (88줄) |
| `app/services/parsers/*.rb` | 기관별 파서 구현 |
| `app/models/financial_institution.rb` | 기관 정보 모델 |
