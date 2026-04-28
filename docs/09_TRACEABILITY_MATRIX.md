# 09 Traceability Matrix

Question ↔ Decision ↔ Requirement ↔ Acceptance/Test ↔ Task 연결.

## Matrix

| TRACE-ID | Question | Decision / ADR | Requirement | AC / Test | Task | Notes |
|---|---|---|---|---|---|---|
| TRACE-001 |  | Implemented behavior | REQ-001 | AC-001 / TEST-001 | Backfill 2026-04-28 | Manual web input creates committed transactions. |
| TRACE-002 |  | Implemented behavior | REQ-002 | AC-002 / TEST-002 | Backfill 2026-04-28 | Text paste creates pending review transactions. |
| TRACE-003 | Q-001 | Partial test evidence; expansion open | REQ-003 | AC-003 / TEST-003 | Backfill 2026-04-28 | Image upload/session behavior is covered; pending review transaction creation assertion and multi-institution accuracy remain open. |
| TRACE-004 |  | Partial implementation | REQ-004 | AC-004 / TEST-004 | Backfill 2026-04-28 | API write scope and tenant boundaries are covered; read-scope enforcement is not yet implemented. |
| TRACE-005 |  | Implemented behavior | REQ-005 | AC-005 / TEST-005 | Backfill 2026-04-28 | Review commit/rollback/discard. |
| TRACE-006 |  | Implemented behavior | REQ-006 | AC-006 / TEST-005, TEST-006 | Backfill 2026-04-28 | Commit blocked by unresolved duplicates. |
| TRACE-007 | Q-002 | Partial test evidence; expansion open | REQ-007 | AC-007 / TEST-007 | Backfill 2026-04-28 | Mapping/keyword behavior is covered; image Gemini fallback and text no-fallback decision-boundary assertions remain open. |
| TRACE-008 |  | Implemented behavior | REQ-008, NFR-003 | AC-008 / TEST-008 | Backfill 2026-04-28 | Workspace role and data isolation. |
| TRACE-009 |  | Implemented behavior | REQ-009 | AC-009 / TEST-009 | Backfill 2026-04-28 | Listing/filter/export behavior. |
| TRACE-010 |  | Implemented behavior | REQ-010, NFR-002 | AC-010 / TEST-010 | Backfill 2026-04-28 | AI consent and toggles. |
| TRACE-011 |  | Implemented behavior | REQ-011 | AC-011 / TEST-011 | Backfill 2026-04-28 | Unsupported file rejection. |
| TRACE-012 |  | Implemented behavior | NFR-001 | AC-012 / TEST-012 | Backfill 2026-04-28 | API key digest/revocation checks. |
| TRACE-013 | Q-003 | Open question | Metrics section |  | Backfill 2026-04-28 | Metric names exist; instrumentation contract is not yet defined. |

## Invariants

- 모든 `must` requirement는 최소 한 개의 acceptance criterion을 가져야 한다.
- 모든 accepted DEC/ADR은 영향을 받는 requirement, HLD, runbook, current doc 중 하나 이상을 명시한다.
- 제품 스코프, 아키텍처, 런타임, 운영 동작을 바꾸는 multi-PR task는 trace row를 가진다.

## Gaps

- TRACE-013: 초기 지표는 이름만 있고 측정 위치/대시보드 계약이 없다. [Q-003](07_QUESTIONS_REGISTER.md#q-003-초기-지표를-어디에서-어떻게-측정할-것인가)을 따른다.
- TRACE-004: API read endpoints authenticate API keys but do not yet call `require_scope!(:read)`, so REQ-004/AC-004 remains pending until read-scope enforcement and negative tests are added.
- TRACE-003: image upload tests do not yet assert that `FileParsingJob` creates `pending_review` transactions from uploaded images, so AC-003 remains pending.
- TRACE-007: category tests do not yet assert the image-path Gemini fallback or text-path no-fallback boundary, so AC-007 remains pending.
- Historical design docs는 전량 backfill하지 않았다. 현재 제품 계약으로 확실한 구현 표면만 추적했다.
