# 06 Acceptance Tests

요구사항이 만족되었는지 검증하는 기준.

검증 명령은 [current/TESTING.md](current/TESTING.md)가 canonical이다. 이 문서는 요구사항과 scenario/test ID의 연결을 관리한다.

## Criteria

| ID | REQ/NFR | Scenario | Verification | Status |
|---|---|---|---|---|
| AC-001 | REQ-001 | Given a writer in a workspace, When they submit the manual transaction form, Then a transaction is created and redirected to the workspace ledger without a parsing session. | automated TEST-001 | pass |
| AC-002 | REQ-002 | Given AI text parsing is enabled and consented, When pasted text is parsed, Then transactions are created as `pending_review` with `source_type: text_paste` and source metadata stays metadata. | automated TEST-002 | pass |
| AC-003 | REQ-003 | Given AI image parsing is enabled and consented, When an allowed image is uploaded, Then a processed file/session is created and the file parsing job creates pending review transactions. | automated TEST-003 | pass |
| AC-004 | REQ-004, NFR-003 | Given an API key, When read/write endpoints are called, Then read endpoints require `read`, writes require `write`, created transactions are committed, and other workspace data is hidden. | automated TEST-004 covers write scope + tenant boundary; read-scope enforcement gap | pending |
| AC-005 | REQ-005 | Given a completed parsing session, When the user commits, rolls back, or discards it, Then transaction statuses and existing originals are updated according to the review action. | automated TEST-005 | pass |
| AC-006 | REQ-006 | Given pending duplicate confirmations, When commit is requested, Then commit is blocked until duplicates are resolved; resolved duplicate decisions are honored. | automated TEST-005, TEST-006 | pass |
| AC-007 | REQ-007 | Given transactions with merchants/descriptions, When category matching runs, Then mapping and keyword matches are deterministic; image path can batch Gemini fallback, text path does not call Gemini category fallback. | automated TEST-007 | pass |
| AC-008 | REQ-008, NFR-003 | Given users with owner/co_owner/member_write/member_read roles, When workspace resources are accessed, Then read/write/admin gates enforce the role boundary and category workspace validation. | automated TEST-008 | pass |
| AC-009 | REQ-009 | Given existing transactions, When list/export filters are used, Then year/month/category/search filters are applied consistently and CSV omits source/institution columns by default. | automated TEST-009 | pass |
| AC-010 | REQ-010, NFR-002 | Given AI feature toggles or consent are disabled, When text/image parsing is requested, Then the request is refused or redirected before AI work is queued. | automated TEST-010 | pass |
| AC-011 | REQ-011 | Given unsupported or spoofed files, When uploaded as statements, Then model validation rejects them by extension, content type, size, or magic bytes. | automated TEST-011 | pass |
| AC-012 | NFR-001 | Given API key lifecycle operations, When keys are generated, authenticated, or revoked, Then only HMAC digests are stored and revoked/invalid/blank tokens fail. | automated TEST-012 | pass |

## Tests

| ID | Name | Location | Covers |
|---|---|---|---|
| TEST-001 | Manual transaction controller flow | `test/controllers/transactions_controller_test.rb` | AC-001, AC-009 |
| TEST-002 | Text paste parsing job behavior | `test/jobs/ai_text_parsing_job_test.rb` | AC-002, AC-007 |
| TEST-003 | Image upload/session/job behavior | `test/controllers/parsing_sessions_controller_test.rb`, `test/jobs/file_parsing_job_test.rb` | AC-003, AC-010 |
| TEST-004 | API key transaction and summary endpoints | `test/controllers/api/v1/transactions_controller_test.rb`, `test/controllers/api/v1/summaries_controller_test.rb` | AC-004 partial: write scope + tenant boundary; no read-scope negative tests yet |
| TEST-005 | Review commit/rollback/discard flow | `test/controllers/reviews_controller_test.rb`, `test/integration/parsing_review_flow_test.rb` | AC-005, AC-006 |
| TEST-006 | Duplicate detector behavior | `test/services/duplicate_detector_test.rb`, `test/jobs/file_parsing_job_test.rb` | AC-006 |
| TEST-007 | Category matching and mapping behavior | `test/models/category_test.rb`, `test/models/category_mapping_test.rb`, `test/jobs/file_parsing_job_test.rb`, `test/jobs/ai_text_parsing_job_test.rb` | AC-007 |
| TEST-008 | Workspace roles and tenant boundary | `test/models/user_test.rb`, `test/models/workspace_membership_test.rb`, `test/controllers/workspace_memberships_controller_test.rb`, `test/models/transaction_test.rb` | AC-008 |
| TEST-009 | Transaction index/export filters | `test/controllers/transactions_controller_test.rb` | AC-009 |
| TEST-010 | AI consent and feature toggles | `test/controllers/parsing_sessions_controller_test.rb`, `test/models/workspace_test.rb` | AC-010 |
| TEST-011 | Processed file validation | `test/models/processed_file_test.rb` | AC-011 |
| TEST-012 | API key model security | `test/models/api_key_test.rb` | AC-012 |

## Definition of Done

- 모든 `must` requirement는 최소 한 개의 acceptance criterion을 가진다.
- 모든 accepted criterion은 named manual check 또는 automated test로 검증된다.
- 운영상 중요한 시나리오는 [05_RUNBOOK.md](05_RUNBOOK.md) 또는 [current/OPERATIONS.md](current/OPERATIONS.md)에 연결된다.
- Traceability row는 [09_TRACEABILITY_MATRIX.md](09_TRACEABILITY_MATRIX.md)에 갱신된다.
