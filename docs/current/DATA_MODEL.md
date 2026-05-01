# Data Model

xef-scale의 도메인 데이터를 한 페이지에서 파악하기 위한 문서. 권위 있는 출처는 [db/schema.rb](../../db/schema.rb), [db/migrate/](../../db/migrate/), 그리고 [app/models/](../../app/models/)입니다. 충돌 시 코드/스키마가 이깁니다.

## Source of truth

- 스키마 정의: [db/schema.rb](../../db/schema.rb) — `db:schema:load`로 재생성됨.
- 변경 이력: [db/migrate/](../../db/migrate/).
- 모델 검증·관계·콜백: [app/models/](../../app/models/).

이 문서는 위에서 *현재* 추출한 형태이며, 새 마이그레이션이 들어오면 같은 PR에서 갱신해야 합니다 ([docs/DOCUMENTATION.md](../DOCUMENTATION.md) 참조).

## 핵심 모델

| 모델 | 테이블 | 핵심 컬럼 | 주요 관계 |
|------|--------|----------|----------|
| `User` | `users` | email, encrypted_password, provider, uid, name, avatar_url, settings | `has_many :workspace_memberships`; Devise + OmniAuth |
| `Workspace` | `workspaces` | name, owner_id, ai_text_parsing_enabled, ai_image_parsing_enabled, ai_category_suggestions_enabled, ai_consent_acknowledged_at | owner는 `User`. `has_many :workspace_memberships, :members, :transactions, :categories, :category_mappings, :parsing_sessions, :processed_files, :api_keys`; `has_one :budget` |
| `WorkspaceMembership` | `workspace_memberships` | user_id, workspace_id, role | role ∈ {`owner`, `co_owner`, `member_write`, `member_read`} |
| `WorkspaceInvitation` | `workspace_invitations` | workspace_id, invited_by_id, token, expires_at, max_uses, current_uses | 토큰 기반 초대 |
| `Transaction` | `transactions` | workspace_id, date, amount, merchant, description, category_id, financial_institution_id, parsing_session_id, status, payment_type, source_type, installment_*, deleted, parse_confidence, source_metadata | `belongs_to :workspace, :category?, :financial_institution? (legacy optional), :parsing_session?, :committed_by(User)?` |
| `Category` | `categories` | workspace_id, name, color, keyword | `has_many :transactions, :category_mappings` |
| `CategoryMapping` | `category_mappings` | workspace_id, category_id, merchant_pattern, description_pattern, match_type, amount, source, dedup_signature | match_type ∈ {`exact`, `contains`}, source ∈ {`import`, `gemini`, `manual`} |
| `ParsingSession` | `parsing_sessions` | workspace_id, processed_file_id?, source_type, status, review_status, started_at, completed_at, committed_at, rolled_back_at, *_count, notes | `has_many :duplicate_confirmations, :transactions, :notifications` |
| `ProcessedFile` | `processed_files` | workspace_id, uploaded_by_id, filename, original_filename, file_hash, institution_identifier, status | `has_one :parsing_session`, `has_one_attached :file` |
| `DuplicateConfirmation` | `duplicate_confirmations` | parsing_session_id, original_transaction_id, new_transaction_id, status, match_confidence, match_score | status ∈ {`pending`, `keep_both`, `keep_original`, `keep_new`} |
| `FinancialInstitution` | `financial_institutions` | name, identifier, institution_type | identifier 유니크. 8개 시드 (신한카드/하나카드/삼성카드/토스뱅크/토스페이/카카오뱅크/카카오페이/새마을금고) |
| `Notification` | `notifications` | user_id, workspace_id, notification_type, title, message, action_url, notifiable_*, read_at | 폴리모픽 `notifiable` |
| `Comment` | `comments` | transaction_id, user_id, body, edited_at | `transactions.comments_count` 카운터 캐시 |
| `AllowanceTransaction` | `allowance_transactions` | expense_transaction_id, user_id | (expense_transaction_id, user_id) 유니크 |
| `Budget` | `budgets` | workspace_id, monthly_amount | 워크스페이스당 1개. 워크스페이스 설정에서 생성/수정하며 blank 저장은 삭제(예산 해제) |
| `ApiKey` | `api_keys` | workspace_id, name, key_digest, key_prefix, scopes, last_used_at, revoked_at | scopes ∈ {`read`, `write`} (CSV) |

ActiveStorage 시스템 테이블(`active_storage_attachments`, `active_storage_blobs`, `active_storage_variant_records`)은 표준이며 별도 설명 없음.

## 모델 관계

```
User ──< WorkspaceMembership >── Workspace
                                 │
                                 ├── Category ──< CategoryMapping
                                 ├── Transaction ──> Category
                                 │           ──> FinancialInstitution
                                 │           ──> ParsingSession
                                 │           ──> User (committed_by)
                                 │           ──< Comment ──> User
                                 │           ──< AllowanceTransaction ──> User
                                 ├── ParsingSession ──> ProcessedFile?
                                 │                 ──< DuplicateConfirmation ──> Transaction (original / new)
                                 │                 ──< Notification
                                 ├── ProcessedFile ──> User (uploaded_by)
                                 │                ──[ActiveStorage]── file
                                 ├── WorkspaceInvitation ──> User (invited_by)
                                 ├── Budget
                                 └── ApiKey
```

`FinancialInstitution`은 워크스페이스 스코프가 아닌 글로벌 시드 데이터. `transactions.financial_institution_id` 컬럼은 기존 데이터를 위해 유지되지만, 현재 파서/리뷰 흐름은 금융기관을 핵심 도메인 필드가 아니라 `transactions.source_metadata` 안의 import hint로 취급한다.

## Transaction 라이프사이클

```
        ┌────────────────────────────────┐
        │                                │
[빌드]──┤── direct entry ────────────────┴──► committed (즉시)
        │
        │── api write ────────────────────► committed (즉시)
        │
        │── parsing job (text/image) ────► pending_review staging
                                              │
                                              ├──► committed   (auto-post finalizer, or legacy review commit)
                                              │
                                              ├──► pending_review (duplicate candidate bridge)
                                              │
                                              ├──► rolled_back (review.rollback 또는 keep_original 결정)
                                              │
                                              └──► (discard) rolled_back for auto-posted rows, destroy for remaining pending rows

Current P1 transition ([ADR-0001](../decisions/ADR-0001-auto-post-imports.md)): complete parsed rows are staged as `pending_review` during duplicate detection and then `ParsingSession#auto_commit_ready_transactions!` immediately promotes rows with date/merchant/amount present, no pending duplicate confirmation, and no same-session exact duplicate group to `committed`. The session only flips to `review_status: committed` when no import exceptions remain. Duplicate candidates still use the legacy review bridge until `INP-1B.2`; date/merchant/amount-missing rows still use the legacy bridge or `ParsingSession#notes` until `INP-1B.3` adds a durable repair model.
```

추가 축:
- `deleted: true` (soft delete) — `Transaction#soft_delete!` / `restore!`. `active` 스코프는 `deleted=false AND status='committed'`만 본다.
- `payment_type` ∈ {`lump_sum`, `installment`, `coupon`}. installment가 아니면 `installment_*` 필드는 자동 nil 처리.
- `source_type` ∈ {`manual`, `text_paste`, `image_upload`, `api`, `import`}. `import`는 향후 일괄 가져오기 등에 예약됨 (현재 마이그레이션/시드에서 사용처 미확인).

## 워크스페이스 경계

- `Transaction.category_id`는 `category.workspace_id == transaction.workspace_id`인지 모델 검증 (`category_belongs_to_workspace`).
- `CategoryMapping.category_id`도 동일 검증.
- API v1 컨트롤러는 모든 쿼리를 `current_workspace.transactions`로 시작해 워크스페이스 경계를 강제한다.

## 카테고리 학습 루프

- `CategoryMapping.source`:
  - `manual` — 사용자가 직접 거래 카테고리를 바꿀 때 학습 (`TransactionsController`와 `ReviewsController`의 단건/일괄 카테고리 변경 흐름).
  - `gemini` — `FileParsingJob`이 `GeminiCategoryService` 결과를 매핑으로 저장.
  - `import` — 일괄 가져오기에서 학습. 단일 호출 지점: `lib/tasks/import.rake`의 `import:build_mappings` 태스크.
- `CategoryMapping.find_for_merchant`는 4단계 우선순위 (exact+amount → exact+nil amount → contains+amount → contains+nil amount). `description_pattern`은 일부 매칭 헬퍼에서 추가 사용.

자세한 흐름은 [CATEGORIZATION.md](CATEGORIZATION.md).

## 검토/중복 상태 머신

현재 코드 기준:

`ParsingSession`:
- `status` ∈ {`pending`, `processing`, `completed`, `failed`}
- `review_status` ∈ {`pending_review`, `committed`, `rolled_back`, `discarded`}
- `source_type` ∈ {`file_upload`, `text_paste`}

게이트:
- `can_commit?` = `completed? && review_pending? && !has_unresolved_duplicates?`
- `can_rollback?` = `completed? && review_committed?`
- `can_discard?` = `completed? && review_pending?`
- `auto_commit_ready_transactions!` = 날짜/가맹점/금액이 모두 있고 duplicate 후보 또는 같은 세션 exact duplicate group이 아닌 `pending_review` 거래를 즉시 `committed`로 바꾸고, 남은 pending row와 import exception이 없으면 세션 `review_status`도 `committed`로 전환.

`DuplicateConfirmation.status` ∈ {`pending`, `keep_both`, `keep_original`, `keep_new`}.

P1 target에서는 `review_status`가 사용자-facing gate가 아니며, `ParsingSession`은 import batch 감사·통계·undo/recovery 컨테이너로 남는다. 현재는 non-duplicate complete row만 auto-post되고, 중복은 아직 legacy review에 남는다.

## 인덱스 / 유니크 제약 (참고)

- `transactions`: `(workspace_id, date)`, `(workspace_id, date, amount)`, `(workspace_id, status)`, `(workspace_id, category_id)`, `(date, merchant, amount)`, `source_type`, `status`.
- `category_mappings`: `(workspace_id, dedup_signature)` UNIQUE — NULL amount race 방지를 위해 `dedup_signature`를 calculated.
- `api_keys`: `key_digest` UNIQUE; `(workspace_id, revoked_at)` 인덱스.
- `notifications`: `(user_id, created_at)`, `(user_id, read_at)` 등.
- `financial_institutions.identifier` UNIQUE.
- `users.email` UNIQUE.

## 확인된 부수 사실

- `Notification.create_parsing_complete!` / `create_parsing_failed!` / `create_budget_alert!` — `app/models/notification.rb`에 클래스 메서드로 정의되어 있다. 예산 알림 호출 조정은 `BudgetAlertService`가 담당한다.
- `CategoryMapping(source: "import")`의 단일 생성 지점은 `lib/tasks/import.rake`(Step 2: 카테고리 매핑 import). 다른 호출 경로는 없다.
- `Workspace.ai_consent_acknowledged_at`을 갱신하는 UI는 `app/views/workspaces/settings.html.erb` + `WorkspacesController#update`이며, true로 캐스팅된 `consent` 파라미터가 들어왔을 때만 시각을 기록한다.
- `ParsingSession#processed_file`이 `optional: true`인 이유: `source_type: "text_paste"` 세션은 파일이 없기 때문 (`source_type: "file_upload"` 세션만 `processed_file` 보유).

## Needs audit

- `Transaction.source_type = "import"`의 실제 사용 지점 — 모델에는 enum 값으로 선언돼 있으나 `app/`, `lib/`, `db/` 어디에서도 이 값으로 거래를 만드는 코드가 없다 (예약 값으로 보이며 향후 일괄 가져오기 거래 import 시 사용 의도 추정).
