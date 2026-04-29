# xef-scale 아키텍처

> 본 문서는 *현재* 시스템의 큰 그림이다. 더 짧은 핵심 요약은 [docs/context/current-state.md](context/current-state.md), 입력→파싱→커밋 동작 세부는 [docs/current/RUNTIME.md](current/RUNTIME.md), 데이터 모델은 [docs/current/DATA_MODEL.md](current/DATA_MODEL.md), AI 호출 정책은 [docs/current/AI_PIPELINE.md](current/AI_PIPELINE.md), 카테고리화는 [docs/current/CATEGORIZATION.md](current/CATEGORIZATION.md). 코드/스키마와 충돌하면 코드/스키마가 권위다.

xef-scale은 한국 금융기관의 지출 내역을 **직접 입력**, **금융 문자 붙여넣기**, **명세서 스크린샷 업로드**, **API write** 네 경로로 받는 Rails 기반 지출 추적 앱입니다. 텍스트/이미지 파싱에는 Gemini를 쓰지만, Gemini 카테고리 폴백은 현재 이미지 경로에만 적용합니다. Excel/PDF/CSV/HTML 명세서는 지원하지 않습니다.

## 핵심 데이터 흐름

```
사용자 (Google OAuth2)
    │
    ▼
Workspace (멀티테넌트 단위)
    │
    ├─► 직접 입력 ─────────────────────────────► Transaction (committed)
    │
    ├─► API write ────────────────────────────► Transaction (committed)
    │
    ├─► 텍스트 붙여넣기 ─► AiTextParsingJob ─► AiTextParser (Gemini Flash)
    │
    └─► 이미지 업로드 (ProcessedFile, JPG/PNG/WEBP/HEIC)
           │
           ▼
        FileParsingJob (Solid Queue)
           │
           └─► ImageStatementParser ─► GeminiVisionParserService (Gemini Vision)
    │
    ▼
Transaction 생성 (pending_review)
    │
    ├─► CategoryMapping 매칭 (exact/contains + amount 우선순위)
    ├─► Category.keyword 매칭 (partial match)
    └─► GeminiCategoryService (이미지 경로의 미분류 잔여분만)
    │
    ▼
중복 감지 → DuplicateConfirmation
    │
    ▼
사용자 리뷰 (ParsingSession)
    │
    ├─► commit! → status: committed  (pending duplicates 없어야 함)
    └─► rollback! → status: rolled_back
```

## 핵심 모델

| 모델 | 역할 |
|------|------|
| **Workspace** | 사용자 그룹의 비용 관리 단위. 모든 데이터의 루트 |
| **Transaction** | 파싱된 거래 기록. 날짜, 금액, 상점, 카테고리 |
| **Category** | 거래 분류 (식비, 교통 등). keyword 필드로 부분 매칭 지원 |
| **CategoryMapping** | 상점명 → 카테고리 매핑 규칙. source: import/gemini/manual |
| **ParsingSession** | 텍스트/파일 파싱 세션. 상태 관리 및 통계 추적 |
| **ProcessedFile** | 업로드된 파일 (ActiveStorage) |
| **FinancialInstitution** | 금융기관 정보. 이미지 파서는 현재 신한카드 명세서 스크린샷을 타깃으로 함 |

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
| AiTextParser | `app/services/ai_text_parser.rb` | 금융 문자 → 거래 구조화 (Gemini Flash) |
| ImageStatementParser | `app/services/image_statement_parser.rb` | 업로드된 이미지를 Gemini Vision에 전달하고 결과 정규화 |
| GeminiVisionParserService | `app/services/gemini_vision_parser_service.rb` | Gemini Vision API 호출 |
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
- ActiveStorage (이미지 저장)
- Devise + OmniAuth (인증)
- Google Gemini API (텍스트 파싱 / 이미지 파싱 / 카테고리화)

## 관련 문서

- [카테고리화 전략](current/CATEGORIZATION.md): 3단계 카테고리 매칭 로직
