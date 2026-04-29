# 09 Traceability Matrix

Question ↔ Decision ↔ Requirement ↔ Gate/Test ↔ Milestone/Track/Phase/Slice 연결.

## Matrix

| TRACE-ID | Question | Decision / ADR | Requirement | Gate / Test | Milestone | Track | Phase | Slice | Notes |
|---|---|---|---|---|---|---|---|---|---|
| TRACE-001 |  | Implemented behavior | REQ-001 | AC-001 / TEST-001 | P0-M1 | REQ | REQ-1A | REQ-1A.1 | Manual web input creates committed transactions. |
| TRACE-002 |  | Implemented behavior | REQ-002 | AC-002 / TEST-002 | P0-M1 | REQ | REQ-1A | REQ-1A.1 | Text paste creates pending review transactions. |
| TRACE-003 | Q-001 | Partial test evidence; expansion open | REQ-003 | AC-003 / TEST-003 | P0-M1 | REQ | REQ-1A | REQ-1A.1 | Image upload/session behavior is covered; pending review transaction creation assertion and multi-institution accuracy remain open. |
| TRACE-004 |  | Implemented behavior | REQ-004 | AC-004 / TEST-004 | P0-M1 | REQ | REQ-1A | REQ-1A.1 | API read/write scopes and tenant boundaries are covered. |
| TRACE-005 |  | Implemented behavior | REQ-005 | AC-005 / TEST-005 | P0-M1 | REQ | REQ-1A | REQ-1A.1 | Review commit/rollback/discard. |
| TRACE-006 |  | Implemented behavior | REQ-006 | AC-006 / TEST-005, TEST-006 | P0-M1 | REQ | REQ-1A | REQ-1A.1 | Commit blocked by unresolved duplicates. |
| TRACE-007 | Q-002 | Partial test evidence; expansion open | REQ-007 | AC-007 / TEST-007 | P0-M1 | REQ | REQ-1A | REQ-1A.1 | Mapping/keyword behavior is covered; image Gemini fallback and text no-fallback decision-boundary assertions remain open. |
| TRACE-008 |  | Implemented behavior | REQ-008, NFR-003 | AC-008 / TEST-008 | P0-M1 | REQ | REQ-1A | REQ-1A.1 | Workspace role and data isolation. |
| TRACE-009 |  | Implemented behavior | REQ-009 | AC-009 / TEST-009 | P0-M1 | REQ | REQ-1A | REQ-1A.1 | Listing/filter/export behavior. |
| TRACE-010 |  | Implemented behavior | REQ-010, NFR-002 | AC-010 / TEST-010 | P0-M1 | REQ | REQ-1A | REQ-1A.1 | AI consent and toggles. |
| TRACE-011 |  | Implemented behavior | REQ-011 | AC-011 / TEST-011 | P0-M1 | REQ | REQ-1A | REQ-1A.1 | Unsupported file rejection. |
| TRACE-012 |  | Implemented behavior | NFR-001 | AC-012 / TEST-012 | P0-M1 | REQ | REQ-1A | REQ-1A.1 | API key digest/revocation checks. |
| TRACE-013 | Q-003 | Open question | Metrics section |  | P0-M1 | REQ | REQ-1A | REQ-1A.1 | Metric names exist; instrumentation contract is not yet defined. |

## Invariants

- 모든 `must` requirement는 최소 한 개의 acceptance criterion을 가져야 한다.
- 모든 accepted DEC/ADR은 영향을 받는 requirement, HLD, runbook, current doc 중 하나 이상을 명시한다.
- 모든 완료 Slice는 적어도 하나의 trace row 또는 [04_IMPLEMENTATION_PLAN.md](04_IMPLEMENTATION_PLAN.md)의 evidence를 가진다.
- 모든 `accepted` milestone은 gate / test evidence를 가진다.

## Gaps

- TRACE-013: 초기 지표는 이름만 있고 측정 위치/대시보드 계약이 없다. [Q-003](07_QUESTIONS_REGISTER.md#q-003-초기-지표를-어디에서-어떻게-측정할-것인가)을 따른다.
- TRACE-003: image upload tests do not yet assert that `FileParsingJob` creates `pending_review` transactions from uploaded images, so AC-003 remains `not_run`.
- TRACE-007: category tests do not yet assert the image-path Gemini fallback or text-path no-fallback boundary, so AC-007 remains `not_run`.
- Historical design docs는 전량 backfill하지 않았다. 현재 제품 계약으로 확실한 구현 표면만 추적했다.
