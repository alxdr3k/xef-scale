# Current State

xef-scale의 현재 구현을 한 페이지로 요약합니다. 미래의 구현 에이전트는 이 문서를 가장 먼저 읽어야 합니다. 코드/스키마와 충돌하면 코드/스키마가 권위입니다.

## 제품

한국 금융 기관(카드/은행)의 지출 내역을 추적하는 Rails 8 웹 앱. 워크스페이스 기반 멀티테넌트, 가족/팀 공유, AI 기반 텍스트·이미지 파싱.

자세한 스코프는 [PRD.md](../../PRD.md).

## 현재 입력 경로 (전체 입력 표면)

세 가지 경로뿐입니다.

1. **직접 입력 (manual)** — 웹 폼에서 `TransactionsController#new/#create`가 즉시 `committed` 상태의 `Transaction`을 만든다. 파싱 세션·검토 흐름을 거치지 않는다.
2. **금융 문자 붙여넣기 (text_paste)** — `ParsingSessionsController#text_parse` → `AiTextParsingJob` → `AiTextParser` (Gemini Flash). 결과는 `pending_review` 상태의 `Transaction`.
3. **명세서 스크린샷 업로드 (image_upload)** — `ParsingSessionsController#create` → `FileParsingJob` → `ImageStatementParser` → `GeminiVisionParserService` (Gemini Vision). 결과는 `pending_review` 상태의 `Transaction`.

API write 경로 (`POST /api/v1/transactions`, `Transaction#source_type = "api"`)도 존재한다. API 키 + `write` 스코프로 인증하며 즉시 `committed` 상태로 저장한다.

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

워크스페이스별 토글: `Workspace.ai_text_parsing_enabled`, `ai_image_parsing_enabled`, `ai_category_suggestions_enabled`. 모두 기본값 true. 첫 사용 시 `Workspace.ai_consent_acknowledged_at`이 nil이면 동의 화면으로 리다이렉트.

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
| `Transaction` | 거래 — `pending_review` / `committed` / `rolled_back`, `source_type` 5종, `payment_type` 3종, `source_metadata` import hint, `classification_source` 결정 메커니즘 4값 (ADR-0011, nullable, set 로직은 후속 PR) |
| `Category` / `CategoryMapping` | 카테고리 + 학습된 매핑 (4단계 우선순위) |
| `ParsingSession` | 파싱 작업 컨테이너, `source_type: file_upload \| text_paste`, 검토 상태 머신 보유 |
| `ProcessedFile` | 업로드된 이미지 파일 — 이미지 외 거부 |
| `DuplicateConfirmation` | 중복 후보 + 결정 (`pending` / `keep_both` / `keep_original` / `keep_new`). 중복 의심 흐름의 authoritative source — 본 모델만 commit gate에 들어감 |
| `ImportIssue` | 가져오기 예외 (`open` / `resolved` / `dismissed`). 현재 `missing_required_fields`만 operational. 사용자가 채우면 새 `pending_review` Transaction으로 승격, 제외 시 `dismissed`. 본 모델도 commit gate 차단 (해당 타입에 한정). `ambiguous_duplicate` 분기는 현재 미생성 — D1 정책에 따라 중복은 `DuplicateConfirmation`에 위임 |
| `Notification` | 인앱 알림 (파싱 완료/실패 등) |
| `Comment` | 거래별 댓글 |
| `AllowanceTransaction` | 거래를 사용자 용돈으로 마킹 |
| `Budget` | 워크스페이스 월 예산 (단일 레코드) |
| `ApiKey` | API/MCP 인증 |
| `FinancialInstitution` | 8개 시드 |

자세히는 [data-model.md](../data-model.md), 권위 있는 출처는 [db/schema.rb](../../db/schema.rb)와 `app/models/`.

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

이 우선순위는 시간이 지나면 빠르게 stale 됩니다. 현재 권위 있는 우선순위는 `PRD.md` + 머지된 ADR + 최근 커밋입니다.

### i18n + `.html_safe` 정책

Phase 6 migration 으로 HTML 이 필요한 번역이 늘었다 (count span, link interpolation, static rich text). 호출지에서 `.html_safe` 가 흩어지면 XSS audit 부담이 커지므로 다음 정책을 적용한다.

- **키 이름.** `.html_safe` 로 마킹되는 translation 키는 반드시 `_html` 로 끝나야 한다. `test/contracts/html_safe_translation_policy_test.rb` 가 회귀를 잠근다.
- **사용 컨텍스트.** `_html` 키는 body 컨텍스트 (라벨/span/본문) 에서만 사용한다. attribute (`data-*`, `title`, `aria-*`) 에 박지 않는다 (Rails 가 HTML-safe 로 마킹된 값을 attribute escape 우회 통로로 만들 수 있음 — `parsing_sessions.note_panel.amount` 가 참조 케이스).
- **interpolation 내용.** 현재 모든 `_html` 키 interpolation 은 (1) integer count, (2) static span, (3) `link_to` 같은 Rails helper output. user input 이 흘러오는 경로는 없다. 새 interpolation 을 추가할 때는 source 가 1·2·3 중 하나라는 사실을 PR 설명에 명시한다.
- **확장 시.** body context rich text 가 더 복잡해지면 `safe_t_html` / `safe_join` / `content_tag` 헬퍼로 통일하는 것이 다음 단계. 지금은 호출 수가 작아 호출지 `.html_safe` 를 유지한다.

### Finalized parsing_session mutation 정책 (Policy A, #220 lock)

`ParsingSession#review_pending?`가 false (committed/rolled_back/discarded) 인 session 의 거래는 다음과 같이 다룬다.

- **Review/import 컨텍스트 mutation 차단.** slideover/inline edit 요청이 `parsing_session_id` 를 함께 보내면 `ReviewsController#reject_if_finalized`, `CategoriesController#new/#create`, `CategoryMappingsController#new/#create` 가 404 로 거부한다.
- **Ledger 컨텍스트 mutation 허용.** 같은 거래라도 `parsing_session_id` 없이 일반 workspace/ledger 편집으로 들어오는 요청은 허용한다. finalize 는 "검토 워크플로 종료"이지 "장부 row 영구 잠금"이 아니므로, 사용자는 finalize 이후에도 카테고리/메모/설명을 수정할 수 있어야 한다.
- **회귀 차단.** `categories_controller_test.rb` 의 `slideover with parsing_session_id` 시리즈가 review-context 거부를, `without_parsing_session_id` 시리즈가 ledger 허용을 잠근다.
- **반대 정책(row 영구 잠금)을 채택하려면** transaction 객체의 `parsing_session.review_pending?` 까지 controller 단에서 검사해야 하며, 이는 본 정책의 변경이다 — 별도 ADR 필요.

### 가져오기 예외 처리 정책 (2026-05-17, B1~B4 완료)

본 라운드(#188~#192)로 incomplete row → `ImportIssue` 분기와 사용자 수리 흐름이 들어왔습니다. 현재 상태:

- `ImportIssue`는 **`missing_required_fields` 한 타입만 operational**. parser가 반환한 row 중 date/merchant/amount가 비어 있는 것을 review queue가 아닌 별도 record로 분기 (#190). 사용자는 review 화면의 수리 섹션(#191/#192)에서 채우거나 제외할 수 있고, 채워진 row는 새 `pending_review` Transaction으로 승격되어 정상 review/commit 흐름에 합류합니다.
- **중복 의심 (`ambiguous_duplicate`) ImportIssue는 현재 생성하지 않습니다 (D1 정책)**. 기존 `DuplicateConfirmation`이 그대로 authoritative source. 둘이 동시에 같은 문제를 표현하면 sync drift가 생기므로 D2(dual marker) / D3(완전 이관)는 채택하지 않음. 본 정책은 [Issue #187](https://github.com/alxdr3k/xef-scale/issues/187) 데이터 검토(2026-07) 결과에 따라 재평가합니다.
- 정상 row의 `auto-post` 여부도 같은 데이터(review에서 commit 전 distinct transaction 기준 수정 비율)로 결정합니다. 그때까지 mandatory review 유지 (Policy B).

review 행동 baseline은 `ImportReviewEvent`(#189)로 수집 중이며, metric 추출은 `lib/tasks/import_review_metrics.rake`(#194)로 제공한다 (status × review_status 분포 + 수정률 + 제외율 + commit latency + ImportIssue 분포).

Phase 1·2·3(`ui-redesign-plan §6`)는 main에 머지됨. preflight([`docs/discovery/2026-05-15-phase-3-ia-preflight.md`](../discovery/2026-05-15-phase-3-ia-preflight.md))의 Bucket A1·A2(ADR-0011)·A3·A4·A5(PR B IA Skeleton)·Phase 3.3 검토함 시트 통합·Phase 3.2 classification_source set 로직·Phase 3.4 카테고리+학습된 매핑 결합·Phase 3.5 더보기 전용 페이지 closure 완료. Phase 4 완료 — Hero stat 채택 + ReviewInboxCard + VarianceCard + RecurringPaymentCard. Phase 5 진행 중 — `User#theme` (settings JSON, auto/light/dark) + 더보기 페이지 테마 토글 + `html[data-theme]` 활성화 (ADR-0008) + 글로벌 `:focus-visible` 룰(시맨틱 `--color-focus` 토큰) + 검토함 키보드 단축키 (j/k navigation + c commit + ? help overlay). 컨트라스트 감사 + 추가 단축키(d/x/enter)는 후속 슬라이스. 다음 사이클은 Phase 5 다크 모드 & a11y / Phase 6 i18n / Phase 7 메트릭.

## Needs audit

다음 항목은 본 PR에서 검증하지 못했거나, 추가 확인이 필요합니다.

- ~~**이미지 파서 멀티 기관 지원** — `ImageStatementParser`의 `institution_identifier`는 컨트롤러에서 전달 가능하지만 (`params[:institution_identifier]`), Vision 프롬프트 자체는 신한카드 명세서 텍스트에 종속됨~~ — [ADR-0009](../decisions/ADR-0009-vision-multi-institution-validation-via-dogfood.md)으로 결정됨. 사전 코퍼스 없이 dogfood로 점진 검증, 회귀 시 케이스별 fixture 누적.
- ~~`Pundit::Authorization` include는 mount만 되어 있고 활성 정책 디렉토리/`authorize` 호출은 0건~~ — [ADR-0001](../decisions/ADR-0001-defer-pundit-adoption.md)으로 결정됨. 현재 패턴 유지, 재검토 트리거는 ADR 참조.
- **PRD.md의 모델 폴백 체인 vs 코드** — `AiTextParser`는 4모델, `GeminiCategoryService`는 5모델, `GeminiVisionParserService`는 1모델. PRD/디자인 문서가 코드와 일치한다고 단정하지 않음.
- **`docs/categorization.md`의 "텍스트 경로는 1-2단계만"** — 코드와 일치하지만, 향후 Gemini 카테고리 폴백을 텍스트 경로에도 적용할지 여부는 미결정.
- **MCP server 등록 방법** — `mcp-server.json`은 정의 파일이지만 실제 등록 방식(`.mcp.json`과의 관계 포함)은 본 PR에서 검증하지 않음.
- ~~ActiveStorage blob 보존/삭제 정책 — 파싱 완료/실패/discard 후 원본 이미지 blob의 정리 정책 미검증~~ — [ADR-0002](../decisions/ADR-0002-active-storage-blob-retention.md)으로 정책 결정됨 (종결 + 180일 후 자동 purge). 구현은 별도 후속 작업.
