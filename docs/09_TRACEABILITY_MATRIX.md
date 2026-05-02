# 09 Traceability Matrix

Question ↔ Decision ↔ Requirement ↔ Gate/Test ↔ Milestone/Track/Phase/Slice 연결.

## Matrix

| TRACE-ID | Question | Decision / ADR | Requirement | Gate / Test | Milestone | Track | Phase | Slice | Notes |
|---|---|---|---|---|---|---|---|---|---|
| TRACE-001 |  | Implemented behavior | REQ-001 | AC-001 / TEST-001 | P0-M1 | REQ | REQ-1A | REQ-1A.1 | Manual web input creates committed transactions. |
| TRACE-002 |  | [ADR-0001](decisions/ADR-0001-auto-post-imports.md) | REQ-002 | AC-002 / TEST-002 | P1-M1 | REQ/INP | REQ-1B / INP-1B | REQ-1B.1, INP-1B.1 | Text paste complete rows auto-post to committed unless they become duplicate candidates. |
| TRACE-003 | Q-001 | [ADR-0001](decisions/ADR-0001-auto-post-imports.md); expansion open | REQ-003 | AC-003 / TEST-003 | P1-M1 | REQ/INP | REQ-1B / INP-1B | REQ-1B.1, INP-1B.1, INP-1B.3 | Image upload complete rows auto-post to committed unless duplicate candidates; incomplete rows are durable `ImportIssue` repair records. |
| TRACE-004 |  | Implemented behavior | REQ-004 | AC-004 / TEST-004 | P0-M1 | REQ | REQ-1A | REQ-1A.1 | API read/write scopes and tenant boundaries are covered. |
| TRACE-005 |  | [ADR-0001](decisions/ADR-0001-auto-post-imports.md) | REQ-005 | AC-005 / TEST-005 | P1-M1 | REQ/UX/INP | REQ-1B / UX-1B / INP-1B | UX-1B.2, UX-1B.3, UX-1B.4, INP-1B.4 | Mandatory review commit/rollback/discard is superseded by focused repair and import-level undo/recovery. |
| TRACE-006 |  | [ADR-0001](decisions/ADR-0001-auto-post-imports.md) | REQ-006 | AC-006 / TEST-005, TEST-006 | P1-M1 | REQ/INP | REQ-1B / INP-1B | INP-1B.2 | Commit blocking by unresolved duplicates is superseded by automatic duplicate policy and duplicate repair issues. |
| TRACE-007 | Q-002 | Implemented behavior; expansion open | REQ-007 | AC-007 / TEST-007 | P0-M1 | REQ | REQ-1A | REQ-1A.1 | Mapping/keyword behavior, image Gemini fallback, and text no-fallback boundary are covered; future text-path Gemini fallback remains a product decision. |
| TRACE-008 |  | Implemented behavior | REQ-008, NFR-003 | AC-008 / TEST-008 | P0-M1 | REQ | REQ-1A | REQ-1A.1 | Workspace role and data isolation. |
| TRACE-009 |  | Implemented behavior | REQ-009 | AC-009 / TEST-009 | P0-M1 | REQ | REQ-1A | REQ-1A.1 | Listing/filter/export behavior. |
| TRACE-010 |  | Implemented behavior | REQ-010, NFR-002 | AC-010 / TEST-010 | P0-M1 | REQ | REQ-1A | REQ-1A.1 | AI consent and toggles. |
| TRACE-011 |  | Implemented behavior | REQ-011 | AC-011 / TEST-011 | P0-M1 | REQ | REQ-1A | REQ-1A.1 | Unsupported file rejection. |
| TRACE-012 |  | Implemented behavior | NFR-001 | AC-012 / TEST-012 | P0-M1 | REQ | REQ-1A | REQ-1A.1 | API key digest/revocation checks. |
| TRACE-013 | Q-003 | Open question | Metrics section |  | P0-M1 | REQ | REQ-1A | REQ-1A.1 | Metric names exist; instrumentation contract is not yet defined. |
| TRACE-014 | Q-008 | DEC-001 | Operational reliability | ROAD-004 | P1-M4 | OPS | OPS-1A | OPS-1A.6..OPS-1A.9 | Current backup helper is dev/import-only; reliable STG/PRD backup/restore remains open. |
| TRACE-015 |  | [ADR-0001](decisions/ADR-0001-auto-post-imports.md) | REQ-002, REQ-003, REQ-005, REQ-006 | ROAD-001 | P1-M1 | REQ/INP/UX | REQ-1B / INP-1B / UX-1B | REQ-1B.1, INP-1B.1..INP-1B.4, UX-1B.1..UX-1B.6 | Mandatory import review is superseded by auto-posted normal rows and focused repair for exceptions. |

## Invariants

- 모든 `must` requirement는 최소 한 개의 acceptance criterion을 가져야 한다.
- 모든 accepted DEC/ADR은 영향을 받는 requirement, HLD, runbook, current doc 중 하나 이상을 명시한다.
- 모든 완료 Slice는 적어도 하나의 trace row 또는 [04_IMPLEMENTATION_PLAN.md](04_IMPLEMENTATION_PLAN.md)의 evidence를 가진다.
- 모든 `accepted` milestone은 gate / test evidence를 가진다.

## Gaps

- TRACE-013: 초기 지표는 이름만 있고 측정 위치/대시보드 계약이 없다. [Q-003](07_QUESTIONS_REGISTER.md#q-003-초기-지표를-어디에서-어떻게-측정할-것인가)을 따른다.
- TRACE-014: 운영 DB 백업/복구 정책은 아직 열려 있다. [Q-008](07_QUESTIONS_REGISTER.md#q-008-운영-db-백업복구의-rporto보관-정책은-무엇인가)을 따른다.
- TRACE-015: ADR과 PRD/AC docs now describe the target contract. Complete-row auto-post and incomplete-row persistence have landed; duplicate policy, repair surfacing/editing, undo/recovery, and review-route removal remain in `INP-1B`/`UX-1B`.
- Historical design docs는 전량 backfill하지 않았다. 현재 제품 계약으로 확실한 구현 표면만 추적했다.
