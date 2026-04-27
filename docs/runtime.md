# Runtime Flow

xef-scale에서 거래가 어떻게 들어와서 저장되는지에 대한 현재 동작 설명. 권위 있는 출처는 코드 (특히 [app/jobs/](../app/jobs/), [app/services/](../app/services/), [app/controllers/parsing_sessions_controller.rb](../app/controllers/parsing_sessions_controller.rb), [app/controllers/reviews_controller.rb](../app/controllers/reviews_controller.rb)).

## 입력 경로 요약

```
직접 입력 ──────────────────────────────────────────► committed Transaction (review skip)

텍스트 붙여넣기 ─► AiTextParsingJob ─► AiTextParser (Gemini Flash) ─┐
                                                                    ├─► pending_review Transaction ─► review ─► committed
이미지 업로드 ──► FileParsingJob ──► ImageStatementParser ─────────┤
                                     └► GeminiVisionParserService   │
                                                                    │
API write ──────────────────────────────────────────────────────────┴─► committed Transaction (review skip)
```

## 1. 직접 입력 (manual)

1. 사용자가 `/workspaces/:id/transactions/new` 폼을 채움.
2. `TransactionsController#create`가 `Transaction`을 빌드하고 `source_type ||= "manual"`을 설정.
3. 모델 검증 통과 시 즉시 `status: "committed"` (Transaction 모델 기본값)으로 저장.
4. 카테고리가 변경되었거나 신규 매핑이 가능하면 `CategoryMapping(source: "manual")`이 생성/업데이트됨.
5. 파싱 세션·중복 감지를 거치지 않는다.

## 2. 텍스트 붙여넣기 (text_paste)

### 2.1 등록

1. 사용자가 `/workspaces/:id/parsing_sessions`의 텍스트 붙여넣기 폼에 SMS/문자 텍스트를 입력.
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
   - `find_institution(name)` — `FinancialInstitution.name LIKE %name%` (sanitize 적용).
   - `match_category(workspace, merchant)` — `CategoryMapping.find_for_merchant` → `Category#matches?`. **여기서 Gemini 카테고리 호출은 없다.**
   - `Transaction.create!`(`source_type: "text_paste"`, `status: "pending_review"`, `parse_confidence`, `parsing_session`).
4. 각 거래 생성 후 `DuplicateDetector.new(workspace, transaction).find_match`로 기존 거래와 비교. 일치하면 `DuplicateConfirmation(status: "pending", match_confidence, match_score)`을 만들고 카운트 증가.
5. 모든 거래 처리 후 통계 hash로 `parsing_session.complete!(stats)` 또는 결과가 0이면 `fail!`.
6. 완료 시 `Notification.create_parsing_complete!`로 워크스페이스 owner + (`co_owner` / `member_write` / `member_read`)에게 알림.

### 2.3 검토 → 커밋

흐름은 §3.3과 동일.

## 3. 이미지 업로드 (image_upload)

### 3.1 등록

1. 사용자가 `/workspaces/:id/parsing_sessions`의 업로드 폼에 JPG/PNG/WEBP/HEIC 이미지를 첨부 (다중 가능).
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
   - 응답을 정규화: `date`(여러 포맷 시도), `merchant`(strip), `amount`(절댓값), `payment_type`, `installment_*`, `institution_identifier`.
3. `excluded_merchants`(사용자별 설정)가 있으면 해당 가맹점 거래는 결과에서 제외.
4. 거래 생성:
   - `match_category_without_gemini` — `CategoryMapping.find_for_merchant(amount: tx_data[:amount])` → `workspace.categories.find { |c| c.matches?(merchant) }`.
   - `Transaction.create!`(`source_type: "image_upload"`, `status: "pending_review"`, `parse_confidence`, `parsing_session`, ...).
   - `category_id`가 nil이면 `uncategorized_transactions`에 모음.
5. `DuplicateDetector` → `DuplicateConfirmation(status: "pending")` (텍스트 경로와 동일).
6. **Gemini 카테고리 폴백**:
   - `uncategorized_transactions.any? && workspace.ai_category_suggestions_enabled?`일 때만.
   - `GeminiCategoryService.new.suggest_categories_batch(merchants, workspace.categories)` — 5모델 폴백.
   - 매칭된 카테고리는 `Transaction#update!(category:)`로 갱신, `CategoryMapping(source: "gemini", merchant_pattern: merchant, match_type: "exact", amount: nil)`을 학습.
7. 통계 hash로 `parsing_session.complete!(stats)` 또는 0건이면 `fail!`. 실패 시 `mark_failed!` + `create_failure_notifications`.

### 3.3 검토 → 커밋 (텍스트·이미지 공통)

1. 사용자가 `/workspaces/:id/parsing_sessions/:id/review` 페이지를 열어 거래·중복 후보를 확인.
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
   - 예산 알림 검사 (`check_budget_alerts`).
5. `ReviewsController#rollback` — 이미 커밋된 세션을 되돌림. `keep_new`로 soft delete된 원본은 `restore!`로 복구.
6. `ReviewsController#discard` — 미커밋 세션을 폐기. `pending_review` 거래를 모두 destroy.

## 4. API write 경로

1. `POST /api/v1/transactions` — `Authorization: Bearer xef_...` 헤더 + `write` 스코프 필요.
2. `Api::V1::TransactionsController#create`가 `current_workspace.transactions.build(create_params)`로 빌드.
3. `transaction.status = "committed"`, `committed_at = Time.current`, `source_type = "api"`로 설정 후 저장.
4. 검토/중복 감지/카테고리화는 호출하지 않는다 — 외부 시스템이 책임.

## 5. 카테고리화 결정 로직

`docs/categorization.md` 참조. 요약:

- 텍스트 경로: `CategoryMapping` → `Category#matches?`. 더 이상 진행하지 않는다.
- 이미지 경로: `CategoryMapping` → `Category#matches?` → 미분류 잔여분에 대해 `GeminiCategoryService` 일괄 호출 (워크스페이스 토글 ON일 때).
- 직접 입력 / API write: 카테고리는 사용자/클라이언트가 직접 지정. 직접 입력 시 변경된 카테고리는 `CategoryMapping(source: "manual")`로 학습.

## 6. 중복 처리

- 감지: `DuplicateDetector.new(workspace, transaction).find_match`. 정확한 비교 기준은 [duplicate_detector.rb](../app/services/duplicate_detector.rb).
- 결정: `DuplicateConfirmation.status` ∈ {`pending`, `keep_both`, `keep_original`, `keep_new`}.
- 적용 시점: 사용자가 `commit`을 누를 때 트랜잭션 내에서 일괄 적용. 결정 자체는 원본/새 거래에 즉시 영향을 주지 않는다 (discard·rollback 시 복구 가능).

## 7. 실패 / 복구

| 상황 | 동작 |
|------|------|
| `GEMINI_API_KEY` 미설정 | 모든 AI 서비스가 생성자에서 `ArgumentError`. `FileParsingJob`의 `categorize_with_gemini_batch`는 `ArgumentError` rescue로 카테고리 0건 반환 (파싱 자체는 Vision까지 진행되어 별도로 실패). `AiTextParsingJob`은 `rescue => e` (StandardError) 절이 `AiTextParser.new`의 `ArgumentError`까지 잡아 `parsing_session.fail!`로 세션을 실패 처리하지만 **잡 자체는 정상 종료**한다. |
| Gemini 텍스트 모델 전체 실패 | `AiTextParser#parse`가 `{ transactions: [], model_used: nil }` 반환 → `AiTextParsingJob`이 0건으로 처리해 `parsing_session.fail!`. 잡은 정상 종료. |
| Gemini Vision 실패 | `GeminiVisionParserService`가 `ApiError` raise → `FileParsingJob`의 `rescue => e`가 잡아 세션 fail + 파일 mark_failed + `Notification.create_parsing_failed!`. 잡은 정상 종료. |
| 이미지 외 파일 업로드 | `ProcessedFile` 모델 검증 실패. 컨트롤러는 success/failed 카운트만 표시. |
| 매직 바이트 불일치 | 같이 거부됨. |
| 중복 미해결 상태에서 커밋 시도 | `ReviewsController#commit`이 alert로 거부. |
| 사용자가 검토 중 거래를 롤백·삭제하면서 중복 결정도 같이 있는 경우 | `ParsingSession#apply_duplicate_decisions!`가 `new_tx.rolled_back? \|\| new_tx.deleted` 일 때 결정 무시. |
| 잡 자체가 예외로 죽음 | `ensure` 블록이 `ParsingSession`을 `fail!`, `ProcessedFile`을 `mark_failed!`로 보정 시도. |

## 8. 데이터 흐름 부수 효과

- 모든 거래 입력 경로가 `CategoryMapping`을 학습/갱신할 수 있다 (manual/import/gemini source 분리).
- **파싱 완료 시점**(잡이 `parsing_session.complete!`을 호출할 때)에 `Notification.create_parsing_complete!`로 멤버(owner + `co_owner` / `member_write` / `member_read`)에게 알림이 발송된다. 검토 단계의 `ReviewsController#commit` / `ParsingSession#commit_all!`는 알림을 만들지 않는다.
- 파싱 실패는 owner + `co_owner` / `member_write` 멤버에게 `Notification.create_parsing_failed!` 알림.
- `ParsingSession`은 `Turbo::Broadcastable`로 상태 변경 시 워크스페이스 채널에 turbo-stream broadcast.
- `ProcessedFile`은 `completed`/`failed` 상태가 되면 pending 리스트에서 제거되도록 broadcast remove.

알림 클래스 메서드는 `app/models/notification.rb`의 `Notification.create_parsing_complete!`, `Notification.create_parsing_failed!`, `Notification.create_budget_alert!`로 정의돼 있다.
