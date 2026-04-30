# Current State

xef-scale의 현재 구현을 한 페이지로 요약합니다. 미래의 구현 에이전트는 이 문서를 가장 먼저 읽어야 합니다. 코드/스키마와 충돌하면 코드/스키마가 권위입니다.

## 제품

한국 금융 기관(카드/은행)의 지출 내역을 추적하는 Rails 8 웹 앱. 워크스페이스 기반 멀티테넌트, 가족/팀 공유, AI 기반 텍스트·이미지 파싱.

자세한 스코프는 [01_PRD.md](../01_PRD.md).

## Current Roadmap Position

- current milestone: `P1-M1` in progress — mobile web self-serve input observation and UX hardening.
- active track / phase / slice: `UX` / `UX-1A` / next recommended slice `UX-1A.1` for the external observation session; ad-hoc feedback is recorded as short leaf slices when it is concrete and locally decidable.
- last accepted gates: `INS-1A.3` monthly dashboard hierarchy audit; `UX-1A.7`, `UX-1A.8`, `INS-1A.5`, and `INP-1A.6` feedback regressions are covered by controller/service/job/e2e checks.
- next gate: `ROAD-001` — observed non-engineer mobile web input → review → commit loop, with blockers recorded as slices.
- canonical ledger: [04_IMPLEMENTATION_PLAN.md](../04_IMPLEMENTATION_PLAN.md).

## 현재 입력 경로 (전체 입력 표면)

네 가지 경로뿐입니다.

1. **직접 입력 (manual)** — 웹 폼에서 `TransactionsController#new/#create`가 즉시 `committed` 상태의 `Transaction`을 만든다. 파싱 세션·검토 흐름을 거치지 않는다.
2. **금융 문자 붙여넣기 (text_paste)** — `ParsingSessionsController#text_parse` → `AiTextParsingJob` → `AiTextParser` (Gemini Flash). 결과는 `pending_review` 상태의 `Transaction`.
3. **명세서 스크린샷 업로드 (image_upload)** — `ParsingSessionsController#create` → `FileParsingJob` → `ImageStatementParser` → `GeminiVisionParserService` (Gemini Vision). 결과는 `pending_review` 상태의 `Transaction`.
4. **API write (api)** — `Api::V1::TransactionsController#create` (`POST /api/v1/transactions`)가 API 키 + `write` 스코프로 인증하고 즉시 `committed` 상태의 `Transaction`을 만든다.

## 명시적으로 스코프 밖

- Excel (.xls/.xlsx), CSV, PDF, HTML 명세서 업로드 — `ProcessedFile` 모델이 모델 레벨에서 이미지 외 확장자/콘텐츠 타입을 거부한다.
- 이메일(SMTP)/IMAP 수집
- 크롤러 / 마이데이터 API 연동
- 로컬 디렉토리 감시(watchdog) 형 파서

## 구현된 파이프라인

### 텍스트 붙여넣기 → 검토 → 커밋

1. 사용자가 `parsing_sessions/index`에서 텍스트 붙여넣기 폼에 SMS/문자 텍스트 입력 (≤ 10,000자).
2. `ParsingSession`이 `source_type: "text_paste"`, `status: "pending"`, `review_status: "pending_review"`로 생성됨. 원문은 `notes` 컬럼에 저장.
3. `AiTextParsingJob`이 `AiTextParser`로 Gemini Flash 호출. 응답을 `Transaction`(`source_type: "text_paste"`, `status: "pending_review"`)으로 정규화하여 저장한다. 금융기관/앱명은 `transactions.source_metadata` 안의 import hint로만 저장하며 핵심 도메인 필드로 승격하지 않는다.
4. 각 거래에 대해 카테고리 매칭: `CategoryMapping.find_for_merchant` → `Category#matches?` (`Category.keyword`). **텍스트 경로는 Gemini 카테고리 폴백을 호출하지 않는다.**
5. `DuplicateDetector`가 동일 워크스페이스의 기존 거래와 비교해 `DuplicateConfirmation`을 만든다.
6. 사용자는 `reviews/show`에서 거래를 확인하고 중복을 해결한 뒤 `commit` 한다. 미해결 중복이 있으면 `ReviewsController#commit`이 거부한다.

### 이미지 업로드 → 검토 → 커밋

1. 사용자가 JPG/PNG/WEBP/HEIC 이미지를 업로드. `ProcessedFile`이 ActiveStorage로 저장되고 모델 레벨에서 확장자/콘텐츠 타입/매직바이트 검증을 통과해야 한다 (≤ 20MB).
2. `FileParsingJob`이 `ImageStatementParser`(기본 `institution_identifier: "shinhan_card"`) → `GeminiVisionParserService`로 Gemini Vision 호출. 현재 프롬프트는 **신한카드 이용대금 명세서**에 맞춰져 있다.
3. 파싱 결과는 `Transaction`(`source_type: "image_upload"`, `status: "pending_review"`)으로 저장한다. 스크린샷 경로도 `source_metadata`를 사용하지만, `institution_identifier` 같은 parser hint를 기본 UI에 노출하지 않는다.
4. 카테고리 매칭은 3단계: `CategoryMapping` → `Category#matches?` → 미분류 잔여분에 대해 `GeminiCategoryService.suggest_categories_batch`로 일괄 추천 (워크스페이스의 `ai_category_suggestions_enabled?`가 true일 때).
5. Gemini 분류 결과는 `CategoryMapping(source: "gemini")`로 저장되어 다음 동일 가맹점에서는 1단계에서 재사용된다.
6. 중복 감지 → `DuplicateConfirmation` → 사용자 검토 → 커밋. 흐름은 텍스트 경로와 동일.

### 직접 입력

1. `TransactionsController#new`가 새 폼을 렌더링하고 `create`가 `source_type ||= "manual"`로 즉시 `committed` 상태의 거래를 만든다.
2. 카테고리 변경 시 `CategoryMapping`이 학습된다 (`source: "manual"`).
3. 파싱/검토 단계가 없다.

## 현재 AI 사용

| 호출 지점 | 호출 시점 | 모델 폴백 체인 |
|----------|----------|--------------|
| `AiTextParser` | 텍스트 붙여넣기 파싱 잡 | `gemini-3-flash-preview` → `gemini-2.5-flash-preview-09-2025` → `gemini-2.5-flash` → `gemini-2.5-flash-lite` |
| `GeminiVisionParserService` | 이미지 파싱 잡 | `gemini-2.5-flash` (단일 모델) |
| `GeminiCategoryService` | 이미지 경로의 미분류 거래 일괄 분류 | `gemini-3-flash-preview` → `gemini-2.5-flash-preview-09-2025` → `gemini-2.5-flash` → `gemini-2.5-flash-lite-preview-09-2025` → `gemini-2.5-flash-lite` |

워크스페이스별 토글: `Workspace.ai_text_parsing_enabled`, `ai_image_parsing_enabled`, `ai_category_suggestions_enabled`. 모두 기본값 true. `Workspace.ai_consent_acknowledged_at`이 nil이면 결제 추가 화면은 텍스트/파일 입력 패널을 숨기고 설정 페이지 동의 CTA만 보여준다. 서버 액션도 같은 조건에서 설정 페이지로 리다이렉트한다.

`GEMINI_API_KEY` 환경변수가 비어 있으면 모든 AI 서비스가 `ArgumentError`로 실패한다.

## 지원 금융기관

`FinancialInstitution::SUPPORTED_INSTITUTIONS` 시드 (`app/models/financial_institution.rb`):

- 신한카드 (`shinhan_card`)
- 하나카드 (`hana_card`)
- 토스뱅크 (`toss_bank`)
- 토스페이 (`toss_pay`)
- 카카오뱅크 (`kakao_bank`)
- 카카오페이 (`kakao_pay`)
- 삼성카드 (`samsung_card`)
- 새마을금고 (`mg_bank`)

| 기관 | 텍스트 경로 (SMS/붙여넣기) | 이미지 경로 (스크린샷) |
|------|--------------------------|----------------------|
| 신한카드 | LLM 범용 — 양식 제약 없음 | **현재 프롬프트가 맞춰져 있음** (이용대금 명세서) |
| 그 외 | LLM 범용 | **needs audit** — `ImageStatementParser`의 기본 식별자가 `shinhan_card`이고 Vision 프롬프트가 신한 명세서 양식에 종속됨 |

`docs/design-phase-a.md`에 등장하는 ShinhanCardParser, HanaCardParser, TossBankParser, KakaoBankParser, SamsungCardParser, MgBankParser, HanaCardHtmlParser, ParserRouter 등은 **현재 코드에 존재하지 않는다**. Phase B 결정으로 모두 제거됨 (`docs/design-phase-b.md` 참조).

## API / MCP

- 인증: `ApiKey` (Bearer 토큰, `xef_` prefix). 스코프: `read`, `write`.
- `GET /api/v1/transactions` — `read` 스코프, 필터 (year/month/category/institution/q/page/per_page).
- `GET /api/v1/transactions/:id` — `read` 스코프.
- `POST /api/v1/transactions` — `write` 스코프, `Transaction.source_type = "api"`로 즉시 커밋.
- `GET /api/v1/summaries/monthly` / `yearly` — `read` 스코프, 월별/연별 집계 (카테고리 breakdown 포함).
- `mcp-server.json` — REST API를 MCP tool로 래핑. `list_transactions`, `get_transaction`, `monthly_summary`, `yearly_summary` 등.

## 데이터 모델 핵심

| 모델 | 역할 |
|------|------|
| `User` | Devise + Google OAuth2 인증 |
| `Workspace` | 멀티테넌트 루트, AI 토글, 동의 시각 보관 |
| `WorkspaceMembership` | 역할: `owner`, `co_owner`, `member_write`, `member_read` |
| `WorkspaceInvitation` | 토큰 기반 초대 (`/join/:token`) |
| `Transaction` | 거래 — `pending_review` / `committed` / `rolled_back`, `source_type` 5종, `payment_type` 3종, `source_metadata` import hint |
| `Category` / `CategoryMapping` | 카테고리 + 학습된 매핑 (4단계 우선순위) |
| `ParsingSession` | 파싱 작업 컨테이너, `source_type: file_upload \| text_paste`, 검토 상태 머신 보유 |
| `ProcessedFile` | 업로드된 이미지 파일 — 이미지 외 거부 |
| `DuplicateConfirmation` | 중복 후보 + 결정 (`pending` / `keep_both` / `keep_original` / `keep_new`) |
| `Notification` | 인앱 알림 (파싱 완료/실패 등) |
| `Comment` | 거래별 댓글 |
| `AllowanceTransaction` | 거래를 사용자 용돈으로 마킹 |
| `Budget` | 워크스페이스 월 예산 (단일 레코드) |
| `ApiKey` | API/MCP 인증 |
| `FinancialInstitution` | 8개 시드 |

자세히는 [DATA_MODEL.md](../current/DATA_MODEL.md), 권위 있는 출처는 [db/schema.rb](../../db/schema.rb)와 `app/models/`.

## 인증·인가

- Devise + OmniAuth Google OAuth2 (`config/initializers/devise.rb`).
- 권한 검사는 `ApplicationController#require_workspace_access` / `require_workspace_write_access` / `require_workspace_admin_access`이며, 내부적으로 `User#can_read?` / `can_write?` / `admin_of?`를 호출한다.
- `Pundit::Authorization`은 `ApplicationController`에 include되어 있지만 **`app/policies/` 디렉토리는 존재하지 않으며, 현재 활성 패턴은 위의 커스텀 role 체크다**.
- API는 `Api::V1::BaseController#authenticate_api_key!`로 별도 인증.

## 현재 우선순위 / 진행 방향

`docs/design-phase-b.md` (2026-03-31 APPROVED, supersedes phase-a)가 가장 최근의 큰 결정 스냅샷. 핵심:

- 모바일 퍼스트 입력. SMS 텍스트 + 스크린샷이 메인 입력.
- Excel/PDF/HTML/CSV 파서 전체 제거 — 완료됨.
- 자체 AI 파싱이 메인. BYOAI는 파워유저용 escape hatch.
- Phase C 수익 모델 (구독/광고/AI 분석) — 별도 설계 예정.

이 우선순위는 시간이 지나면 빠르게 stale 됩니다. 현재 권위 있는 우선순위는 [docs/01_PRD.md](../01_PRD.md) + 머지된 ADR + 최근 커밋입니다.

## Needs audit

다음 항목은 본 PR에서 검증하지 못했거나, 추가 확인이 필요합니다.

- **이미지 파서 멀티 기관 지원** — `ImageStatementParser`의 `institution_identifier`는 컨트롤러에서 전달 가능하지만 (`params[:institution_identifier]`), Vision 프롬프트 자체는 신한카드 명세서 텍스트에 종속됨. 다른 기관 명세서가 들어오면 정확도 저하 가능. 실제 동작 측정 필요.
- **`Pundit::Authorization` include는 mount만 되어 있고 활성 정책 디렉토리/`authorize` 호출은 0건**. 현재 활성 패턴은 `ApplicationController#require_workspace_*` + `User#can_read?` / `can_write?` / `admin_of?`. 향후 정책 도입 시 ADR 권장.
- **docs/01_PRD.md의 모델 폴백 체인 vs 코드** — `AiTextParser`는 4모델, `GeminiCategoryService`는 5모델, `GeminiVisionParserService`는 1모델. PRD/디자인 문서가 코드와 일치한다고 단정하지 않음.
- **`docs/current/CATEGORIZATION.md`의 "텍스트 경로는 1-2단계만"** — 코드와 일치하지만, 향후 Gemini 카테고리 폴백을 텍스트 경로에도 적용할지 여부는 미결정.
- **MCP server 등록 방법** — `mcp-server.json`은 정의 파일이지만 실제 등록 방식(`.mcp.json`과의 관계 포함)은 본 PR에서 검증하지 않음.
- **ActiveStorage blob 보존/삭제 정책** — 파싱 완료/실패/discard 후 원본 이미지 blob의 정리 정책 미검증.
- **DB 백업/복구 프로세스** — `DatabaseBackupService`는 development/test 환경에서만 초기화되는 import 전용 단순 파일 복사 헬퍼다. `SqliteBackupService`는 configured SQLite role 단위의 checkpoint/online backup/integrity_check primitive를 제공하지만, production DB set 스케줄, ActiveStorage blob, 외부 보관, 보존 정책, 복구 리허설은 아직 구현된 신뢰 가능한 프로세스가 아니다.
