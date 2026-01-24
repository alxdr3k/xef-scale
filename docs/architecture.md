# xef-scale 아키텍처

xef-scale은 한국 금융기관의 지출 명세서(Excel/PDF/CSV)를 업로드하여 자동 파싱하고 분류하는 Rails 기반 지출 추적 앱입니다.

## 핵심 데이터 흐름

```
사용자 (Google OAuth2)
    │
    ▼
Workspace (멀티테넌트 단위)
    │
    ▼
ProcessedFile 업로드 (Excel/PDF/CSV)
    │
    ▼
FileParsingJob (비동기, SolidQueue)
    │
    ├─► ParserRouter (기관 식별)
    │       └─► 기관별 Parser (TossBankParser, ShinhanCardParser 등)
    │
    ▼
Transaction 생성 (pending_review)
    │
    ├─► CategoryMapping 매칭 (1순위: exact match)
    ├─► Category.keyword 매칭 (2순위: partial match)
    └─► GeminiCategoryService (3순위: AI 분류)
    │
    ▼
중복 감지 → DuplicateConfirmation
    │
    ▼
사용자 리뷰 (ReviewSession)
    │
    ├─► commit! → status: committed
    └─► rollback! → status: rolled_back
```

## 핵심 모델

| 모델 | 역할 |
|------|------|
| **Workspace** | 사용자 그룹의 비용 관리 단위. 모든 데이터의 루트 |
| **Transaction** | 파싱된 거래 기록. 날짜, 금액, 상점, 카테고리 |
| **Category** | 거래 분류 (식비, 교통 등). keyword 필드로 부분 매칭 지원 |
| **CategoryMapping** | 상점명 → 카테고리 매핑 규칙. source: import/gemini/manual |
| **ParsingSession** | 파일 파싱 세션. 상태 관리 및 통계 추적 |
| **ProcessedFile** | 업로드된 파일 (ActiveStorage) |
| **FinancialInstitution** | 금융기관 정보 (6개: 신한카드, 하나카드, 토스뱅크/페이, 카카오뱅크/페이) |

### 모델 관계

```
Workspace ──┬── Category ──── CategoryMapping
            ├── Transaction ─── FinancialInstitution
            ├── ParsingSession ─── DuplicateConfirmation
            ├── ProcessedFile
            └── WorkspaceMembership ─── User
```

## Workspace 기반 멀티테넌트

- 모든 데이터는 Workspace에 속함
- 사용자는 여러 Workspace의 멤버가 될 수 있음
- 역할 기반 접근 제어: `owner`, `co_owner`, `member_write`, `member_read`

## 핵심 서비스

| 서비스 | 위치 | 역할 |
|--------|------|------|
| ParserRouter | `app/services/parser_router.rb` | 파일 내용 기반 금융기관 식별 및 파서 라우팅 |
| BaseParser | `app/services/parsers/base_parser.rb` | 파서 추상 기본 클래스 |
| GeminiCategoryService | `app/services/gemini_category_service.rb` | AI 기반 카테고리 분류 |

## Transaction 상태 머신

```
pending_review ──► committed (확정)
       │
       └─────────► rolled_back (롤백)
```

- `commit!(user)`: 거래 확정, 감사 추적
- `rollback!`: 거래 롤백

## 기술 스택

- Ruby 3.3+, Rails 8.0+
- SQLite3
- Solid Queue (백그라운드 작업)
- ActiveStorage (파일 저장)
- Devise + OmniAuth (인증)
- Roo, PDF::Reader (파일 파싱)
- Google Gemini API (AI 카테고리화)

## 관련 문서

- [카테고리화 전략](categorization.md): 3단계 카테고리 매칭 로직
- [파서 시스템](parser-system.md): 금융기관별 파서 구현
