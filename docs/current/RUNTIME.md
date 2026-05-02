# Runtime Flow

xef-scale에서 거래가 어떻게 들어와서 저장되는지에 대한 현재 동작 설명. 권위 있는 출처는 코드 (특히 [app/jobs/](../../app/jobs/), [app/services/](../../app/services/), [app/controllers/parsing_sessions_controller.rb](../../app/controllers/parsing_sessions_controller.rb), [app/controllers/reviews_controller.rb](../../app/controllers/reviews_controller.rb)).

## 입력 경로 요약

```
직접 입력 ──────────────────────────────────────────► committed Transaction (review skip)

텍스트 붙여넣기 ─► AiTextParsingJob ─► AiTextParser (Gemini Flash) ─┐
                                                                    ├─► complete row ─► committed
이미지 업로드 ──► FileParsingJob ──► ImageStatementParser ─────────┤
                                     └► GeminiVisionParserService   │
                                                                    ├─► duplicate candidate ─► legacy review
                                                                    ├─► incomplete image row ─► ImportIssue repair record
                                                                    │
API write ──────────────────────────────────────────────────────────┴─► committed Transaction (review skip)
```

전환 목표: [ADR-0001](../decisions/ADR-0001-auto-post-imports.md)은 텍스트/이미지 파싱 결과 중 complete row를 파싱 완료 시점에 자동 `committed`로 저장하고, 필수값 누락·애매한 중복만 repair queue로 보내도록 결정했다. 현재 코드는 non-duplicate complete row를 자동 커밋하고, incomplete image row를 `ImportIssue(status: open)`로 저장한다. Duplicate 후보는 아직 legacy review에 남는다.

## 1. 직접 입력 (manual)

1. 사용자가 `/workspaces/:id/transactions/new` 폼을 채움.
2. `TransactionsController#create`가 `Transaction`을 빌드하고 `source_type ||= "manual"`을 설정.
3. 모델 검증 통과 시 즉시 `status: "committed"` (Transaction 모델 기본값)으로 저장.
4. 이후 `TransactionsController` 또는 `ReviewsController`의 단건/일괄 카테고리 변경 흐름에서 카테고리가 바뀌면 `CategoryMapping(source: "manual")`이 생성/업데이트됨.
5. 파싱 세션·중복 감지를 거치지 않는다.

## 2. 텍스트 붙여넣기 (text_paste)

### 2.1 등록

1. 사용자가 `/workspaces/:id/parsing_sessions`의 텍스트 붙여넣기 폼에 SMS/문자 텍스트를 입력. AI 동의가 아직 필요하면 이 폼은 렌더되지 않고 설정 페이지 동의 CTA만 표시된다.
2. `ParsingSessionsController#text_parse`:
   - 텍스트가 빈 문자열이거나 10,000자 초과면 거부.
   - `Workspace.ai_consent_required?`가 true면 워크스페이스 설정 페이지로 리다이렉트.
   - `Workspace.ai_text_parsing_enabled?`가 false면 거부.
   - `ParsingSession`을 `source_type: "text_paste"`, `status: "pending"`, `review_status: "pending_review"`, `notes: <원문>`으로 생성.
   - `AiTextParsingJob.perform_later(parsing_session.id)` 인큐.

### 2.2 백그라운드 파싱

1. `AiTextParsingJob#perform`이 세션을 `processing`으로 전환 (`ParsingSession#start!`).
2. `AiTextParser.new.parse(notes)`:
   - 모델 폴백 (`gemini-3-flash-preview` → ... → `gemini-2.5-flash-lite`) 중 첫 성공 응답을 사용.
   - JSON schema 강제 (`responseSchema: TRANSACTION_SCHEMA`).
   - 각 거래에서 `is_cancel: true`이면 `amount`를 음수로 뒤집음.
3. 각 거래 dict에 대해:
   - `build_source_metadata(tx_data)` — `source_channel: "pasted_text"`, `source_institution_raw`, `parser_confidence`를 저장. `FinancialInstitution` lookup은 하지 않는다.
   - `match_category(workspace, merchant)` — `CategoryMapping.find_for_merchant` → `Category#matches?`. **여기서 Gemini 카테고리 호출은 없다.**
   - `Transaction.create!`(`source_type: "text_paste"`, initially `status: "pending_review"`, `parse_confidence`, `parsing_session`).
4. 각 거래 생성 후 `DuplicateDetector.new(workspace, transaction).find_match`로 기존 거래와 비교. 일치하면 `DuplicateConfirmation(status: "pending", match_confidence, match_score)`을 만들고 카운트 증가.
5. 결과/성공이 0이면 `fail!` + `create_failure_notifications`.
6. 성공 row가 있으면 `ParsingSession#auto_commit_ready_transactions!`가 pending row 중 날짜/가맹점/금액이 모두 있고, `DuplicateConfirmation.pending`의 `new_transaction`이 아니며, 같은 세션 안의 exact duplicate group에도 속하지 않는 row만 `Transaction#commit!`으로 전환한다. 모든 pending row가 처리되고 import exception(`stats[:error]`)도 없으면 세션 `review_status`도 `committed`가 된다. 미해결 duplicate 후보가 남으면 세션은 `pending_review`로 남는다.
7. 자동 커밋된 거래 월에 대해 `BudgetAlertService.create_for_transactions!`가 예산 알림을 생성하고, `parsing_session.complete!(stats)` 후 `Notification.create_parsing_complete!`로 워크스페이스 owner + (`co_owner` / `member_write` / `member_read`)에게 알림. 이 post-commit side effect는 best-effort이며, 실패해도 이미 커밋된 거래와 completed 세션을 failed로 되돌리지 않는다.

### 2.3 Duplicate 후보 legacy review

Duplicate 후보로 남은 row는 아직 §3.3 legacy review를 사용한다. `INP-1B.2`는 이 경로를 자동 duplicate policy와 repair issue로 대체한다.

## 3. 이미지 업로드 (image_upload)

### 3.1 등록

1. 사용자가 `/workspaces/:id/parsing_sessions`의 업로드 폼에 JPG/PNG/WEBP/HEIC 이미지를 첨부 (다중 가능). AI 동의가 아직 필요하면 이 폼은 렌더되지 않고 설정 페이지 동의 CTA만 표시된다.
2. `ParsingSessionsController#create`:
   - AI 동의 게이트 + `Workspace.ai_image_parsing_enabled?` 체크.
   - 각 파일에 대해 `ProcessedFile`을 빌드하고 ActiveStorage로 첨부.
   - `ProcessedFile` 모델이 확장자, content type, 매직 바이트, 파일 크기(20MB)를 검증. 실패 시 저장하지 않고 카운트.
   - 저장에 성공한 파일에 대해 `FileParsingJob.perform_later(processed_file.id, institution_identifier:)` 인큐. `institution_identifier`는 폼에서 들어오면 사용, 없으면 잡이 기본값 `"shinhan_card"`로 처리.

### 3.2 백그라운드 파싱

1. `FileParsingJob#perform`이 `ProcessedFile`을 `processing`으로 전환하고 `ParsingSession`을 `processing` / `pending_review`로 만든다.
2. `parse_file`:
   - `ImageStatementParser.new(processed_file, institution_identifier:).parse`.
   - 확장자가 이미지가 아니면 `UnsupportedFormatError`로 실패.
   - 파일을 임시 파일로 다운로드한 뒤 `GeminiVisionParserService.new.parse_image(tempfile, mime_type:)` 호출.
   - 응답을 정규화: `date`(여러 포맷 시도), `merchant`(strip), `amount`(절댓값), `payment_type`, `installment_*`, `institution_identifier`(parser hint), `source_institution_raw?`(모델이 실제로 추출했을 때만).
   - 날짜/가맹점/금액 중 필수 정보가 부족한 행은 `incomplete_transactions`로 보존한다. `FileParsingJob`은 이 행을 `Transaction`으로 만들지 않고 `ImportIssue`로 저장한다. `ImportIssue`는 보이는 `date`/`merchant`/`amount`, `missing_fields`, 원본 `parsing_session`, `processed_file`, `source_type`, `raw_payload`, `status`를 가진다. 전부 incomplete라 저장 가능한 거래가 없어도 repair record는 남고 세션/파일은 실패로 표시된다.
3. `excluded_merchants`(사용자별 설정)가 있으면 해당 가맹점 거래는 결과에서 제외.
4. 거래 생성:
   - `match_category_without_gemini` — `CategoryMapping.find_for_merchant(amount: tx_data[:amount])` → `workspace.categories.find { |c| c.matches?(merchant) }`.
   - `Transaction.create!`(`source_type: "image_upload"`, initially `status: "pending_review"`, `parse_confidence`, `parsing_session`, ...).
   - import/source hint는 `transactions.source_metadata`에 저장. `source_institution_raw`는 parser가 실제 원문 기관명을 반환했을 때만 저장하며, `institution_identifier` 같은 내부 parser hint를 그대로 사용자 메타데이터로 노출하지 않는다.
   - `category_id`가 nil이면 `uncategorized_transactions`에 모음.
5. `DuplicateDetector` → `DuplicateConfirmation(status: "pending")` (텍스트 경로와 동일).
6. **Gemini 카테고리 폴백**:
   - `uncategorized_transactions.any? && workspace.ai_category_suggestions_enabled?`일 때만.
   - `GeminiCategoryService.new.suggest_categories_batch(merchants, workspace.categories)` — 5모델 폴백.
   - 매칭된 카테고리는 `Transaction#update!(category:)`로 갱신, `CategoryMapping(source: "gemini", merchant_pattern: merchant, match_type: "exact", amount: nil)`을 학습.
7. 통계 hash로 분기:
   - `stats[:total] > 0`이고 저장 성공이 1건 이상이면 `ParsingSession#auto_commit_ready_transactions!(user: processed_file.uploaded_by)`로 duplicate 후보 없는 row를 자동 `committed` 전환하고, `parsing_session.complete!(stats)` + `processed_file.mark_completed!` 후 best-effort로 `BudgetAlertService.create_for_transactions!` + `create_completion_notifications`.
   - `stats[:total].zero?` 또는 `stats[:success].zero?` → count를 세션에 저장한 뒤 `parsing_session.fail!` + `processed_file.mark_failed!` + `create_failure_notifications`. 이때 incomplete row가 있었다면 `ImportIssue`는 유지된다.
   - 그 외 예외(Vision 호출/저장 등) → 잡 상단의 `rescue => e`가 `parsing_session.fail!` + `processed_file.mark_failed!` + `create_failure_notifications(parsing_session) if parsing_session`를 실행한다.

### 3.3 Legacy review → 커밋 (duplicate 후보 / 전환기 예외)

1. 사용자가 `/workspaces/:id/parsing_sessions/:id/review` 페이지를 열어 거래·중복 후보를 확인. 전환기 동안 open `ImportIssue`가 있으면 같은 화면 상단에 자동 반영되지 않은 항목 요약을 보여준다. focused repair entry point는 `UX-1B.2`/`UX-1B.3`에서 별도로 만든다.
2. 인라인 편집/카테고리 변경/롤백/소프트 삭제는 `ReviewsController#update_transaction`, `ReviewsController#bulk_update`, 거래 컨트롤러의 인라인 액션으로 가능.
3. 중복 결정:
   - `DuplicateConfirmationsController#update` — 단일.
   - `ReviewsController#bulk_resolve_duplicates` — 일괄 (`keep_both` / `keep_original` / `keep_new`).
4. `ReviewsController#commit`:
   - `parsing_session.has_unresolved_duplicates?`이면 거부 (alert 노출).
   - 아니면 `parsing_session.commit_all!(current_user)` 호출.
   - `commit_all!`은 트랜잭션 안에서:
     - `apply_duplicate_decisions!` — `keep_new` 결정은 원본 거래를 soft delete, `keep_original` 결정은 새 거래를 `rollback!`로 표시.
     - 세션의 `pending_review` 거래를 `commit!(user)`로 전환.
     - `review_status: "committed"`로 갱신.
   - 예산 알림 검사 (`BudgetAlertService.create_for_transactions!`): 월 예산이 있고 해당 월 지출이 80% 이상이면 `budget_warning`, 100% 이상이면 `budget_exceeded`.
5. `ReviewsController#rollback` — 이미 커밋된 세션을 되돌림. `keep_new`로 soft delete된 원본은 `restore!`로 복구.
6. `ReviewsController#discard` — pending import 세션을 폐기. 같은 세션에서 이미 auto-committed 된 거래는 `rolled_back`으로 되돌리고, 남은 `pending_review` 거래는 destroy한다.

## 4. API read/write 경로

1. `GET /api/v1/transactions`, `GET /api/v1/transactions/:id`, `GET /api/v1/summaries/monthly`, `GET /api/v1/summaries/yearly` — `Authorization: Bearer xef_...` 헤더 + `read` 스코프 필요.
2. `POST /api/v1/transactions` — `Authorization: Bearer xef_...` 헤더 + `write` 스코프 필요.
3. `Api::V1::TransactionsController#create`가 `current_workspace.transactions.build(create_params)`로 빌드.
4. `transaction.status = "committed"`, `committed_at = Time.current`, `source_type = "api"`로 설정 후 저장.
5. 검토/중복 감지/카테고리화는 호출하지 않는다 — 외부 시스템이 책임.

## 5. 카테고리화 결정 로직

[CATEGORIZATION.md](CATEGORIZATION.md) 참조. 요약:

- 텍스트 경로: `CategoryMapping` → `Category#matches?`. 더 이상 진행하지 않는다.
- 이미지 경로: `CategoryMapping` → `Category#matches?` → 미분류 잔여분에 대해 `GeminiCategoryService` 일괄 호출 (워크스페이스 토글 ON일 때).
- 직접 입력 / API write: 카테고리는 사용자/클라이언트가 직접 지정. 직접 입력 시 변경된 카테고리는 `CategoryMapping(source: "manual")`로 학습.

## 6. 중복 처리

- 감지: `DuplicateDetector.new(workspace, transaction).find_match`. 정확한 비교 기준은 [duplicate_detector.rb](../../app/services/duplicate_detector.rb).
- 결정: `DuplicateConfirmation.status` ∈ {`pending`, `keep_both`, `keep_original`, `keep_new`}.
- 적용 시점: 사용자가 `commit`을 누를 때 트랜잭션 내에서 일괄 적용. 결정 자체는 원본/새 거래에 즉시 영향을 주지 않는다 (discard·rollback 시 복구 가능).
- P1 target: review-time duplicate blocking을 제거하고, import finalizer가 exact duplicate는 자동 제외하고 ambiguous duplicate는 repair issue로 보관한다 (`INP-1B.2`).

## 7. 실패 / 복구

| 상황 | 동작 |
|------|------|
| `GEMINI_API_KEY` 미설정 | 모든 AI 서비스가 생성자에서 `ArgumentError`. `FileParsingJob`의 `categorize_with_gemini_batch`는 `ArgumentError` rescue로 카테고리 0건 반환 (파싱 자체는 Vision까지 진행되어 별도로 실패). `AiTextParsingJob`은 `rescue => e` (StandardError) 절이 `AiTextParser.new`의 `ArgumentError`까지 잡아 `parsing_session.fail!` + `create_failure_notifications`로 세션을 실패 처리하지만 **잡 자체는 정상 종료**한다. |
| Gemini 텍스트 모델 전체 실패 | `AiTextParser#parse`가 `{ transactions: [], model_used: nil }` 반환 → `AiTextParsingJob`이 0건으로 처리해 `parsing_session.fail!` + `create_failure_notifications`. 잡은 정상 종료. |
| Gemini Vision 실패 (예외 raise) | `GeminiVisionParserService`가 개별 모델 실패를 로깅하고 모든 모델 실패 시 `AllModelsFailedError` raise → `FileParsingJob`의 `rescue => e`가 잡아 `parsing_session.fail!` + `processed_file.mark_failed!` + `create_failure_notifications(parsing_session) if parsing_session`. 잡은 정상 종료. |
| Vision은 성공했지만 추출 거래 0건 | `FileParsingJob`이 `stats[:total].zero?` 분기로 진입 → `parsing_session.fail!` + `processed_file.mark_failed!` + `create_failure_notifications`로 owner / `co_owner` / `member_write` 멤버에게 `Notification.create_parsing_failed!` 발송. |
| Vision은 성공했고 incomplete row만 있음 | `ImportIssue`를 저장한 뒤 `stats[:success].zero?` 분기로 진입 → 세션/파일은 failed, 실패 알림은 발송, repair record는 유지. 입력 기록은 "수정 필요" count와 상세보기 링크를 보여주고, 실패 세션 상세 화면은 open `ImportIssue` 요약을 보여준다. |
| 이미지 외 파일 업로드 | `ProcessedFile` 모델 검증 실패. 컨트롤러는 success/failed 카운트만 표시. |
| 매직 바이트 불일치 | 같이 거부됨. |
| 중복 미해결 상태에서 커밋 시도 | `ReviewsController#commit`이 alert로 거부. |
| 사용자가 검토 중 거래를 롤백·삭제하면서 중복 결정도 같이 있는 경우 | `ParsingSession#apply_duplicate_decisions!`가 `new_tx.rolled_back? \|\| new_tx.deleted` 일 때 결정 무시. |
| `FileParsingJob`이 처리 중 예외를 만남 | `rescue => e`와 `ensure` 블록이 `ParsingSession`을 `fail!`, `ProcessedFile`을 `mark_failed!`로 보정 시도한다. `AiTextParsingJob` 내부 예외는 별도 rescue 분기에서 실패 처리한다. |

## 8. 데이터 흐름 부수 효과

- `CategoryMapping` 쓰기는 사용자 수동 카테고리 변경(`source: "manual"`), 이미지 경로의 Gemini 카테고리 폴백(`source: "gemini"`), 일괄 import Rake 태스크(`source: "import"`)에서 발생한다. 텍스트 파싱과 API write 자체는 매핑을 만들지 않는다.
- **월 예산 설정** — 워크스페이스 관리자는 `settings_workspace_path`의 월 예산 폼으로 `Budget.monthly_amount`를 생성/수정한다. 금액을 비워 저장하면 워크스페이스의 Budget 레코드를 삭제해 예산 progress와 예산 알림을 끈다.
- **예산 progress** — `DashboardsController#monthly`가 `Budget#progress_for_month`를 호출해 월별 총 지출 대비 예산 비율을 표시한다. 계산은 active(committed, non-deleted) + non-coupon 거래만 포함한다.
- **월별 대시보드 요약** — `DashboardsController#monthly`는 총 지출 hero 외에 가장 큰 카테고리, 가장 큰 결제, 미분류 건수를 계산해 모바일에서도 먼저 읽을 수 있는 요약 카드로 표시한다.
- **반복 결제 탐지** — `DashboardsController#recurring`이 `RecurringPaymentDetector#detect`를 호출한다. detector는 active(committed, non-deleted) + non-coupon 거래 중 같은 가맹점이 2개월 이상 월간 연속성을 보이고, 금액이 20% 이내로 안정적이거나 결제일 변동 폭이 7일 이내인 경우만 반복 결제로 표시한다. 최근 구간의 마지막 결제가 기준 월에서 2개월보다 오래됐으면 과거에 반복됐더라도 제외한다. 한 달 누락은 허용하지만, 오래된 반복 구간에 최근 단발 결제 하나가 붙은 경우는 반복 결제로 보지 않는다.
- **파싱 완료 알림** — 잡이 `parsing_session.complete!`을 호출한 뒤 `Notification.create_parsing_complete!`이 발송된다. `AiTextParsingJob`은 stats > 0일 때, `FileParsingJob`은 stats > 0일 때. 세션이 자동 `committed` 되었으면 알림 action은 결제 내역(`/transactions`)으로, duplicate 후보나 import exception 때문에 `pending_review`이면 현재는 legacy review로 향한다. `UX-1B.2`가 이 action을 repair-focused surface로 바꾼다. 검토 단계의 `ReviewsController#commit` / `ParsingSession#commit_all!`는 알림을 만들지 않는다. 수신자는 워크스페이스 owner + 멤버 (`co_owner` / `member_write` / `member_read`).
- **파싱 실패 알림** — `AiTextParsingJob`과 `FileParsingJob`은 결과/성공이 0건인 실패 분기와 잡 내부 예외 분기에서 `create_failure_notifications`를 호출해 owner + `co_owner` / `member_write` 멤버에게 `Notification.create_parsing_failed!`을 발송한다. `FileParsingJob`의 예외 경로는 `parsing_session`이 만들어진 뒤에만 알림을 보낼 수 있다.
- **예산 알림** — 자동 커밋된 import 거래와 legacy review commit 거래 모두 `BudgetAlertService.create_for_transactions!`를 통해 영향을 받은 거래 월별로 `Notification.create_budget_alert!`을 호출한다. 80% 이상 100% 미만은 `budget_warning`, 100% 이상은 `budget_exceeded`이며, `workspace_id/user_id/notification_type/target_year/target_month` 조합으로 같은 사용자·월·타입의 중복 알림을 막는다.
- `ParsingSession`은 `Turbo::Broadcastable`로 상태 변경 시 워크스페이스 채널에 turbo-stream broadcast.
- `ProcessedFile`은 `completed`/`failed` 상태가 되면 pending 리스트에서 제거되도록 broadcast remove.

알림 클래스 메서드는 `app/models/notification.rb`의 `Notification.create_parsing_complete!`, `Notification.create_parsing_failed!`, `Notification.create_budget_alert!`로 정의돼 있다.
