# AI Pipeline

> Last verified against code: `8085821` (2026-04-29).
> AI 호출 지점/프롬프트/모델/순서가 바뀌면 같은 PR에서 본 SHA를 갱신한다. 정책: [docs/DOCUMENTATION.md](../DOCUMENTATION.md).

xef-scale에서 LLM(Gemini)을 호출하는 모든 지점, 결정성-우선 정책, 비용 통제 가이드. 카테고리화 단계 자체에 대한 상세는 [CATEGORIZATION.md](CATEGORIZATION.md)를 참고하고, 본 문서는 AI 호출 전반(텍스트 파싱·이미지 파싱·카테고리 추천)을 다룬다.

## 원칙: LLM은 데이터베이스가 아니다

가능한 한 결정적 신호(스키마, 매핑, regex, 모델 상태)로 답을 얻고, **판단·추출이 필요한 경우에만** Gemini를 호출한다. 새 결정/마이그레이션이 이 원칙을 흔든다면 ADR을 만든다.

## 현재 AI 호출 지점

| 서비스 | 호출 시점 | 입력 | 출력 | 폴백 | 비용 통제 |
|--------|----------|------|------|------|----------|
| `AiTextParser` | `AiTextParsingJob` 1회/세션 | 사용자가 붙여넣은 텍스트 (≤ 10,000자) | 구조화된 거래 배열 (JSON schema 강제) | 4 모델 폴백 (`gemini-3-flash-preview` → `gemini-2.5-flash-preview-09-2025` → `gemini-2.5-flash` → `gemini-2.5-flash-lite`) | 워크스페이스 토글 `ai_text_parsing_enabled?`, AI 동의 게이트, temperature=0.1, maxOutputTokens=4096 |
| `GeminiVisionParserService` | `FileParsingJob` 1회/이미지 | 다운로드된 이미지 (jpg/png/webp/heic ≤ 20MB) | 구조화된 거래 배열 + 필수 정보가 부족한 incomplete 거래 후보 (JSON schema 강제) | **없음** — `gemini-2.5-flash` 단일 모델 | 워크스페이스 토글 `ai_image_parsing_enabled?`, AI 동의 게이트, 이미지 모델 검증 (확장자 + content type + 매직 바이트) |
| `GeminiCategoryService` | `FileParsingJob`의 미분류 거래 일괄 처리 | 미분류 가맹점명 unique 리스트 + 워크스페이스 카테고리 | `{ merchant => category_name }` | 5 모델 폴백 (`gemini-3-flash-preview` → ... → `gemini-2.5-flash-lite`) | 워크스페이스 토글 `ai_category_suggestions_enabled?`, 매핑 학습으로 다음 호출 회피, batch 호출, 텍스트 경로는 호출 안함 |

`GEMINI_API_KEY`가 비어 있으면 세 서비스 모두 생성자에서 `ArgumentError`. 잡 측 rescue:
- `AiTextParsingJob` — `rescue => e` (StandardError) 절이 `AiTextParser.new`의 `ArgumentError`를 잡아 `parsing_session.fail!` + `create_failure_notifications`로 세션을 실패 처리한다. **잡 자체는 예외를 다시 던지지 않으므로 ActiveJob 기준 정상 종료**. 운영자는 잡 retry가 아니라 세션 status/실패 알림으로 실패를 인지한다.
- `FileParsingJob` — `categorize_with_gemini_batch`만 `ArgumentError`/`StandardError`를 rescue해 카테고리 0건 처리. Vision 호출에서 발생한 예외는 동일 잡의 `rescue => e`가 잡아 세션 fail + 파일 mark_failed + 실패 알림을 실행한다. 잡 자체는 정상 종료.

## 결정성-우선 카테고리 파이프라인

상세는 [CATEGORIZATION.md](CATEGORIZATION.md). 요점:

1. `CategoryMapping.find_for_merchant` (4단계: exact+amount → exact → contains+amount → contains).
2. `Category#matches?` — 워크스페이스 카테고리의 `keyword` 부분 매칭.
3. (이미지 경로만) `GeminiCategoryService.suggest_categories_batch` — 미분류 잔여분 일괄 호출.

**확인된 동작:**
- 텍스트 경로(`AiTextParsingJob#match_category`)는 1·2단계만 실행한다. Gemini 카테고리 호출 없음.
- 이미지 경로(`FileParsingJob`)는 1·2단계로 결정 못 하면 3단계를 호출한다. 결과는 `CategoryMapping(source: "gemini")`로 저장되어 다음에 1단계에서 재사용.

## 비결정 → 결정 학습 루프

| 입력 | 학습되는 매핑 |
|------|--------------|
| 사용자가 거래의 카테고리를 직접 바꿈 | `CategoryMapping(source: "manual")` (`TransactionsController`와 `ReviewsController`의 단건/일괄 카테고리 변경에서 `create_category_mapping` 호출) |
| Gemini가 가맹점에 카테고리를 추천 | `CategoryMapping(source: "gemini", merchant_pattern: <merchant>, match_type: "exact", amount: nil)` |
| 일괄 가져오기 (Rake 태스크) | `CategoryMapping(source: "import")` — 단일 호출: `lib/tasks/import.rake`의 `import:build_mappings` 태스크 |

다음 동일 가맹점 거래는 결정적 단계에서 매칭되어 Gemini 호출이 발생하지 않는다.

## 후보 최적화 (planned principle, 미구현)

다음은 **현재 코드에 구현되어 있지 않다**. 도입할 가치가 있다고 판단되면 ADR로 결정.

### 1. Cheap classifier + 조건부 LLM 추출

- **현재**: 텍스트 경로는 항상 LLM을 호출한다.
- **후보**: 잘 알려진 한국 금융 SMS 양식(예: 신한카드 SMS, 토스뱅크 출금)은 정규식·간단한 분류기로 결정적 추출이 가능. 모호한 경우만 LLM 폴백.
- **트레이드오프**: 편한가계부형 정규식 유지 비용 vs LLM 비용. Phase B 디자인 ([docs/design-phase-b.md](../design-phase-b.md))은 명시적으로 정규식 트랙을 거부했다. 변경 시 ADR 필요.

### 2. Write-time normalization

- **원칙**: 파싱 시 한 번 정규화된 거래 필드만 저장하고, 이후 검토/리스트/대시보드에서는 원문 텍스트나 이미지를 다시 LLM에 던지지 않는다.
- **현재 상태**: `Transaction`이 정규화된 필드를 모두 저장하고 있고, 검토 페이지(`reviews/show`)는 정규화된 필드만 표시한다 — **암묵적으로 구현됨**.
- **위반 사례 만들지 말 것**: 검토 화면이나 추론 잡에서 `parsing_session.notes` (원문) 또는 ProcessedFile 이미지를 다시 LLM 컨텍스트로 넣지 말 것. 필요하면 ADR로 정당화.

### 3. Prompt prefix 안정성 / 캐싱

- **현재**: `AiTextParser`와 `GeminiCategoryService`는 prompt를 호출 시점마다 빌드한다 (`build_prompt`, `build_batch_prompt`). 캐싱·프리픽스 분리 없음.
- **후보**: 정적 지시(카테고리 정의, 한국 금융 SMS 처리 지침)는 prefix로 분리하고, 가변부(사용자 텍스트, merchant 리스트)만 끝에 붙여 모델/프록시 캐싱 적중률을 높인다. 적용 시 평가용 측정 지표를 함께 정의.

### 4. Context budget tiers

후보 분류:

| 사용 사례 | 티어 | 현재 구현? |
|----------|------|----------|
| 결정적 매핑/keyword 매칭 | LLM 호출 없음 | implemented |
| 카테고리 폴백 | tiny prompt + 짧은 응답 | implemented (이미지 경로 batch) |
| 일반 SMS/스크린샷 파싱 | normal prompt + JSON schema | implemented |
| 신규 카드/기관 양식 조사 | deep — multi-shot, 더 큰 maxOutputTokens, 모델 단계 상승 | planned |

이미지 경로에서 날짜/가맹점/금액 중 필수 정보가 보이지 않는 행은 자동으로 날짜를 추정하지 않는다. Gemini 응답은 보이는 필드만 포함한 `incomplete_transactions`를 반환할 수 있다. 현재 코드는 해당 행을 결제 내역으로 만들지 않고 `ImportIssue(issue_type: "missing_required_fields", status: "open")` repair record로 저장한다. 전부 incomplete여도 세션/파일은 completed로 남고 repair 알림을 보낸다. Text/image complete row가 기존 거래와 애매하게 겹치면 새 거래를 커밋하지 않고 `ImportIssue(issue_type: "ambiguous_duplicate", duplicate_transaction_id: <기존 거래>)`로 저장한다. Open repair record는 post-parse toast, notification dropdown/list, 결제 내역 `repair=required` banner/filter에서 노출된다. Focused repair mode는 누락 필수값을 사용자가 직접 입력하게 하며, 완성된 repair row는 중복 검사 후 committed 거래로 승격하거나 ambiguous duplicate로 전환한다 ([ADR-0001](../decisions/ADR-0001-auto-post-imports.md), `UX-1B.3`, `INP-1B.4`).

`maxOutputTokens` 등 파라미터를 호출 사이트별로 명시적으로 분리하고 싶다면 ADR로 도입 결정.

## 비용 / 지연 추정 (자료 기반)

- 한 명세서 이미지 = Vision 1회.
- 한 텍스트 붙여넣기 = Text parser 1회.
- Gemini Category batch = uncategorized merchant unique 수에 비례한 1회.
- `CategoryMapping` 학습으로 동일 가맹점 재호출 회피.

실제 측정은 `docs/evals/`에 추가하기.

## 외부 데이터 처리

- 사용자 SMS/스크린샷에는 거래 금액·가맹점·카드번호 일부 등 민감 정보가 포함될 수 있다.
- AI 사용 첫 시점에 `Workspace#ai_consent_required?` 게이트가 작동 — `ai_consent_acknowledged_at`이 nil이면 컨트롤러가 설정 페이지로 강제 리다이렉트.
- 워크스페이스별 토글: `ai_text_parsing_enabled`, `ai_image_parsing_enabled`, `ai_category_suggestions_enabled`. 모두 기본 true이지만 켜져 있어도 동의 시각이 없으면 동작 안함.
- 업로드된 이미지는 `Tempfile`로 임시 다운로드되어 처리 후 `unlink`되며, ActiveStorage blob 자체의 보존/삭제는 별도 정책에 따른다 (`needs audit` — 명시적 삭제 정책 코드 미확인).

## 변경 시 체크리스트

새 AI 호출 지점·모델·프롬프트를 추가/수정한다면:

- [ ] 호출 시점·입력·출력을 위 표에 반영.
- [ ] 결정적 폴백이 가능한지 먼저 검토.
- [ ] 워크스페이스 토글 / 동의 게이트가 적용되는지 확인.
- [ ] `needs audit`이 아니라 측정된 정확도/지연을 갖고 있다면 `docs/evals/`에 결과 링크.
- [ ] 모델 폴백 체인은 코드와 이 문서를 동시에 업데이트.

## Needs audit / 후속

- AI 사용량/비용 측정 — 평가 인프라 부재.
- 텍스트 경로에 카테고리 폴백을 도입할지 여부 (ADR 필요 시).
- 이미지 파서의 비-신한 기관 정확도.
- Vision/Text의 캐시 친화 prompt 분리.
