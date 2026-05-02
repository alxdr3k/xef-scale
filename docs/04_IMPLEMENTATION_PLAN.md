# 04 Implementation Plan

제품 gate, 기술 흐름, 구현 slice 상태를 처음부터 끝까지 한 곳에서 시퀀싱한다.

이 문서는 xef-scale의 canonical full-leaf roadmap이자 status ledger다. Issue tracker와 PR은 실행 단위의 토론과 리뷰를 담당하지만, milestone / track / phase / slice / gate / evidence의 최종 인덱스는 이 문서에 남긴다. 구현 단계의 얇은 문서 레이어([context/current-state.md](context/current-state.md), [current/](current/))에는 전체 roadmap inventory를 복제하지 않는다.

## Inputs / Authority

로드맵 작성 시 사용한 입력과 우선순위:

1. 현재 권위: [01_PRD.md](01_PRD.md), [02_HLD.md](02_HLD.md), [current/](current/), 코드, 테스트, 마이그레이션, [db/schema.rb](../db/schema.rb).
2. Gate / trace: [06_ACCEPTANCE_TESTS.md](06_ACCEPTANCE_TESTS.md), [09_TRACEABILITY_MATRIX.md](09_TRACEABILITY_MATRIX.md), [07_QUESTIONS_REGISTER.md](07_QUESTIONS_REGISTER.md).
3. Historical design seed: [design-phase-a.md](design-phase-a.md), [design-phase-b.md](design-phase-b.md). 현재 PRD와 충돌하는 항목은 `dropped` 또는 `deferred`로 표시한다.
4. 새 큰 결정은 [decisions/](decisions/) ADR 또는 [08_DECISION_REGISTER.md](08_DECISION_REGISTER.md)로 승격한다.

## Taxonomy

| Term | Meaning | Example ID | Notes |
|---|---|---|---|
| Milestone | 제품 / 사용자 관점의 delivery gate | `P1-M1` | "사용자가 어떤 상태를 얻는가"를 기준으로 정의 |
| Track | 기술 영역 또는 큰 구현 흐름 | `INP` | docs, requirements, input, API, operations 등 |
| Phase | track 안의 구현 단계 | `INP-1A` | 같은 track 안에서 순서가 있는 단계 |
| Slice / Task | 커밋 가능한 구현 단위 | `INP-1A.2` | PR / commit / issue와 연결 가능한 크기 |
| Gate | 검증 / acceptance 기준 | `AC-012` / `ROAD-001` | 제품 AC는 [06_ACCEPTANCE_TESTS.md](06_ACCEPTANCE_TESTS.md), roadmap gate는 아래 표 |
| Evidence | 완료를 뒷받침하는 근거 | PR, code, tests, current docs | 본문 복제 대신 링크 / ID로 남김 |

## Status Vocabulary

Implementation status:

| Status | Meaning |
|---|---|
| `planned` | 계획됨. 아직 시작 조건이 충족되지 않음 |
| `ready` | 시작 가능. dependency와 scope가 충분히 정리됨 |
| `in_progress` | 구현 또는 문서 작업 진행 중 |
| `landed` | 코드 / 문서 변경이 반영됨 |
| `accepted` | gate를 통과했고 milestone 기준으로 수용됨 |
| `blocked` | blocker 때문에 진행 불가 |
| `deferred` | 의도적으로 뒤로 미룸 |
| `dropped` | 하지 않기로 함 |

Gate status:

| Status | Meaning |
|---|---|
| `defined` | 기준은 정의됐지만 아직 실행하지 않음 |
| `not_run` | 실행 대상이지만 아직 실행하지 않음 |
| `passing` | 통과 |
| `failing` | 실패 |
| `waived` | 명시적 사유로 면제 |

## Feedback Intake

실사용 피드백은 큰 제품 로드맵 밖에서 들어와도 버리지 않는다. 재현 가능한 버그, UX 회귀, 오판정처럼 바로 결정 가능한 항목은 가장 가까운 track/phase의 짧은 leaf slice로 기록하고 같은 PR에서 코드·테스트·current 문서까지 반영한다. 더 큰 제품 방향, 운영 정책, 비용/보안 trade-off가 필요한 항목만 questions register 또는 ADR로 승격한다. 사용자 관찰에서 나온 항목은 `UX-1B.6`/`ROAD-001` evidence로도 남긴다.

## Milestones

| Milestone | Product / user gate | Target | Status | Gate | Evidence | Notes |
|---|---|---|---|---|---|---|
| `P0-M0` | Former PRD baseline before [ADR-0001](decisions/ADR-0001-auto-post-imports.md): manual/text/image/API 입력, 검토, 중복, 카테고리, 워크스페이스 경계, API, 조회/export가 코드와 테스트로 확인됨. | 2026-04-28 | `accepted` | historical AC-001..AC-012 | [06_ACCEPTANCE_TESTS.md](06_ACCEPTANCE_TESTS.md), [current/](current/), tests | Superseded for import UX by P1 `REQ-1B` / `INP-1B` / `UX-1B`; auto-post, duplicate policy, and repair surfacing have landed, while repair editing/promotion, undo/recovery, and review removal remain. |
| `P0-M1` | Current product contract is traced to requirements, acceptance criteria, tests, and open gaps. | 2026-04-28 | `accepted` | link review | `5cecb68`, `a434a35`, `c79e678`; PR #111, PR #112 | Boilerplate structure and requirement traceability backfill landed on `dev`. |
| `P0-M2` | Roadmap/status taxonomy and maintenance-drift workflow are adopted without moving xef-scale canonical implementation docs. | 2026-04-29 | `accepted` | link review + docs review | PR #114, `58b49a4`; PR #115, `36f7bb4`; PR #116, `4cea6ce`; CI | Latest boilerplate migration and ledger cleanup are merged on `dev`. |
| `P1-M1` | Founder/wife can use the mobile web flow end-to-end without engineering help and the team has observation evidence. | next | `in_progress` | `ROAD-001` | `UX-1A.2` mobile nav reachability patch; `INS-1A.1` budget setting/progress/alert audit; `INS-1A.2` recurring-payment audit; `INS-1A.3` monthly dashboard hierarchy; `UX-1A.7`/`UX-1A.8`/`INS-1A.5`/`INP-1A.6` feedback regressions; `REQ-1B.1` product contract update; `INP-1B.2` duplicate policy; `INP-1B.3` durable incomplete-row repair records; `UX-1B.2` repair surfacing; `UX-1B.3` focused repair UI; `INP-1B.4` repair promotion; [ADR-0001](decisions/ADR-0001-auto-post-imports.md) resets the import UX target | First post-ledger execution milestone; mandatory review is being replaced by auto-post + exception repair. |
| `P1-M2` | AI parsing quality, non-Shinhan image risk, text-category policy, and metrics are measured enough to make product decisions. | after P1-M1 | `planned` | `ROAD-002` |  | Resolves or narrows Q-001, Q-002, Q-003. |
| `P1-M3` | Data OS API/MCP surface is reliable enough for BYOAI clients and operationally bounded. | after P1-M2 | `planned` | `ROAD-003` |  | Builds on existing API read/write. |
| `P1-M4` | Operational reliability/privacy gaps for jobs, blobs, backups, imports, and deploy references are closed or explicitly accepted. | after P1-M2 | `planned` | `ROAD-004` |  | Turns current `needs audit` items into decisions/tests. |
| `P2-M1` | Monetization and tier policy are decided and implemented behind explicit billing/entitlement boundaries. | after P1 | `planned` | `ROAD-005` |  | Requires Q-004, Q-006. |
| `P2-M2` | BYOAI/AI analytics can answer deeper trend/family questions through structured app-owned data. | after P1-M3 | `planned` | `ROAD-006` |  | Keep xef-scale as memory/data layer; avoid replacing user AI. |
| `P3-M1` | Native / OS integration direction is decided after platform constraints are rechecked. | later | `deferred` | `ROAD-007` |  | Requires Q-005 and platform spike. |
| `P3-M2` | Institution coverage expands beyond the current web AI wedge only where measured value justifies scope. | later | `deferred` | `ROAD-008` |  | Depends on Q-001 and eval data. |

## Tracks

| Track | Purpose | Active phase | Status | Notes |
|---|---|---|---|---|
| `DOC` | Documentation structure, roadmap ledger, generated docs, and agent guidance | none | `accepted` | Keep full roadmap here; keep current docs thin. |
| `REQ` | Product requirements, acceptance criteria, and traceability | none | `accepted` | P1 import contract has been rewritten from mandatory review to auto-post + repair exceptions; implementation remains in `INP-1B` / `UX-1B`. |
| `BASE` | Existing product baseline and historical Phase A/B implemented surface | none | `accepted` | Current PRD scope only. |
| `UX` | Mobile web UX, family onboarding, input ergonomics | `UX-1B` | `in_progress` | First user-observation milestone now targets auto-post imports and exception repair. |
| `INP` | Input/parsing engines and institution coverage | `INP-1B` | `in_progress` | Text/image AI path exists; complete rows now auto-post; exact duplicates are skipped; ambiguous duplicates and incomplete image rows are durable repair records; focused repair promotion has landed. |
| `CAT` | Categorization and learning loop | `CAT-1A` | `planned` | Text Gemini fallback is an open decision. |
| `API` | API keys, REST API, MCP/data OS integration | `API-1A` | `planned` | API read/write exists; client hardening remains. |
| `INS` | Dashboard, budget, recurring payments, insights | `INS-1A` | `in_progress` | Budget, recurring-payment, and monthly dashboard hierarchy audits accepted; insight ownership decision remains later. |
| `OBS` | Metrics, evals, analytics instrumentation | `OBS-1A` | `ready` | Enables P1 decisions. |
| `OPS` | Privacy, job/deploy reliability, retention, backup/restore, import reconciliation | `OPS-1A` | `planned` | Converts `needs audit` into decisions. |
| `BIZ` | Pricing, entitlement, billing, retention limits, ads | `BIZ-2A` | `planned` | Phase C business model. |
| `NTV` | Native apps, share extension, Android SMS, OS integrations | `NTV-3A` | `deferred` | Not Phase B; revisit after evidence. |
| `DROP` | Explicitly rejected or superseded paths | none | `dropped` | Prevents stale historical designs from re-entering silently. |

## Roadmap Gates

| Gate | Meaning | Status |
|---|---|---|
| `ROAD-001` | Observed non-engineer user completes the mobile web input → auto-posted ledger → exception repair loop, or blockers are recorded as slices. | `defined` |
| `ROAD-002` | Real sample evals exist for text, image, and categorization; Q-001/Q-002/Q-003 have decision records or scoped follow-up slices. | `defined` |
| `ROAD-003` | API/MCP client workflows have tests/docs, rate boundaries, and key-management UX that non-code clients can follow. | `defined` |
| `ROAD-004` | Blob retention, worker process, DB backup/restore, import/source type, deploy placeholder, and AI quota monitoring are decided or tested. | `defined` |
| `ROAD-005` | Free/paid/BYOAI tier policy, billing provider, entitlement gates, retention limits, and ad policy are implemented or explicitly dropped. | `defined` |
| `ROAD-006` | Analytics/BYOAI endpoints support trend, budget, recurring, and family-member questions without sending raw private inputs unnecessarily. | `defined` |
| `ROAD-007` | Native platform constraints are rechecked and Android/iOS/share-extension strategy is accepted, deferred, or dropped. | `defined` |
| `ROAD-008` | Additional institution/receipt coverage has measured accuracy, user value, and maintenance cost before implementation. | `defined` |

## Leaf Roadmap

| Slice | Milestone | Track | Phase | Goal | Depends | Gate | Gate status | Status | Evidence | Next |
|---|---|---|---|---|---|---|---|---|---|---|
| `DOC-1A.1` | `P0-M1` | `DOC` | `DOC-1A` | Adopt boilerplate document structure using xef-scale canonical paths. |  | link review | `passing` | `accepted` | `5cecb68`; PR #111 | Keep wrappers thin. |
| `REQ-1A.1` | `P0-M1` | `REQ` | `REQ-1A` | Backfill product requirements, acceptance criteria, and traceability for implemented behavior. | `DOC-1A.1` | AC/Test trace review | `passing` | `accepted` | `a434a35`, `c79e678`, [06_ACCEPTANCE_TESTS.md](06_ACCEPTANCE_TESTS.md), [09_TRACEABILITY_MATRIX.md](09_TRACEABILITY_MATRIX.md); PR #112 | Expansion questions become separate slices. |
| `DOC-1B.1` | `P0-M2` | `DOC` | `DOC-1B` | Migrate to updated roadmap/status taxonomy and maintenance drift workflow from boilerplate `24851cf` / `24b47f1`. | `DOC-1A.1` | link review + docs review | `passing` | `accepted` | PR #114, `58b49a4` | Complete. |
| `DOC-1B.2` | `P0-M2` | `DOC` | `DOC-1B` | Accept merged roadmap ledger evidence after PR #114. | `DOC-1B.1` | docs review | `passing` | `accepted` | PR #115, `36f7bb4` | Complete. |
| `DOC-1B.3` | `P0-M2` | `DOC` | `DOC-1B` | Remove placeholder risk spike from active ledger. | `DOC-1B.2` | docs review | `passing` | `accepted` | PR #116, `4cea6ce` | Complete. |
| `DOC-1C.1` | `P0-M2` | `DOC` | `DOC-1C` | Expand implementation plan into full leaf roadmap from PRD/HLD/design docs. | user request | markdown link review + roadmap consistency review | `passing` | `accepted` | PR #117, `c66322c`, `e471894` | Complete. |
| `BASE-0A.1` | `P0-M0` | `BASE` | `BASE-0A` | Manual web transaction creation stores committed transactions without parsing sessions. |  | AC-001 | `passing` | `accepted` | [06_ACCEPTANCE_TESTS.md](06_ACCEPTANCE_TESTS.md) | Complete. |
| `BASE-0A.2` | `P0-M0` | `BASE` | `BASE-0A` | Text paste creates `pending_review` transactions through AI parser with consent/toggle gates. |  | AC-002, AC-010 | `passing` | `accepted` | [current/RUNTIME.md](current/RUNTIME.md) | Complete. |
| `BASE-0A.3` | `P0-M0` | `BASE` | `BASE-0A` | Image upload accepts only supported images and creates `pending_review` transactions. |  | AC-003, AC-011 | `passing` | `accepted` | [current/RUNTIME.md](current/RUNTIME.md) | Complete, scoped to current Vision prompt limits. |
| `BASE-0A.4` | `P0-M0` | `BASE` | `BASE-0A` | Review, commit, rollback, discard, and unresolved duplicate blocking are implemented. |  | AC-005, AC-006 | `passing` | `accepted` | [current/RUNTIME.md](current/RUNTIME.md) | Complete. |
| `BASE-0A.5` | `P0-M0` | `BASE` | `BASE-0A` | Workspace RBAC and tenant boundaries are accepted; invitations, comments, notifications, allowance, budget, and recurring-payment code are present but still need product polish/audit slices. |  | AC-008 + current-doc review | `passing` | `landed` | [current/CODE_MAP.md](current/CODE_MAP.md), [current/DATA_MODEL.md](current/DATA_MODEL.md) | Product polish remains in P1. |
| `BASE-0A.6` | `P0-M0` | `BASE` | `BASE-0A` | API read/write and summaries are available with API-key scopes. |  | AC-004, AC-012 | `passing` | `accepted` | [current/RUNTIME.md](current/RUNTIME.md), [mcp-server.json](../mcp-server.json) | Client hardening remains in P1. |
| `CAT-0A.1` | `P0-M0` | `CAT` | `CAT-0A` | CategoryMapping, keyword matching, image Gemini fallback, and no text Gemini category fallback are implemented. |  | AC-007 | `passing` | `accepted` | [current/CATEGORIZATION.md](current/CATEGORIZATION.md) | Measure and decide text expansion in P1. |
| `REQ-1B.1` | `P1-M1` | `REQ` | `REQ-1B` | Rewrite PRD, acceptance tests, traceability, and current docs from mandatory import review/commit to auto-post imports with exception repair and undo. | [ADR-0001](decisions/ADR-0001-auto-post-imports.md) | product contract docs review | `passing` | `accepted` | [01_PRD.md](01_PRD.md), [02_HLD.md](02_HLD.md), [06_ACCEPTANCE_TESTS.md](06_ACCEPTANCE_TESTS.md), [09_TRACEABILITY_MATRIX.md](09_TRACEABILITY_MATRIX.md), [current/RUNTIME.md](current/RUNTIME.md), [current/DATA_MODEL.md](current/DATA_MODEL.md), [current/AI_PIPELINE.md](current/AI_PIPELINE.md), [current/TESTING.md](current/TESTING.md), [context/current-state.md](context/current-state.md) | Complete; code work starts at `INP-1B.1` / `INP-1B.3`. |
| `UX-1A.1` | `P1-M1` | `UX` | `UX-1A` | Observe founder/wife mobile web session from input to commit under the former mandatory-review flow. | `P0-M0` | former `ROAD-001` | `waived` | `dropped` | design Phase A/B assignment | Superseded by [ADR-0001](decisions/ADR-0001-auto-post-imports.md); run `UX-1B.6` instead. |
| `UX-1A.2` | `P1-M1` | `UX` | `UX-1A` | Audit and fix mobile navigation so dashboard, transactions, upload, and settings are reachable on phones. | `P0-M0` | controller mobile nav check + mobile e2e | `passing` | `accepted` | [app/views/layouts/_mobile_bottom_nav.html.erb](../app/views/layouts/_mobile_bottom_nav.html.erb), [test/controllers/dashboards_controller_test.rb](../test/controllers/dashboards_controller_test.rb), [e2e/mobile_navigation.spec.ts](../e2e/mobile_navigation.spec.ts) | Complete. |
| `UX-1A.3` | `P1-M1` | `UX` | `UX-1A` | Audit upload ergonomics: automatic parse start, progress feedback, completion/failure state, and no page-refresh dependency. | `UX-1B.1` | manual UX check + relevant controller/system tests | `defined` | `planned` | design-phase-a Task 1, current Turbo broadcasts | Fold into the no-review completion UX. |
| `UX-1A.4` | `P1-M1` | `UX` | `UX-1A` | Polish invitation onboarding: token join, Google login handoff, role confirmation, failure/expired states. | `P0-M0` | invitation flow test/manual check | `defined` | `planned` | design-phase-a Task 2 |  |
| `UX-1A.5` | `P1-M1` | `UX` | `UX-1A` | Add or update help/guide surfaces for supported input paths and financial-institution caveats. | `UX-1A.3` | docs/UI review | `defined` | `planned` | design-phase-a Task 5 | Avoid reviving Excel/PDF scope. |
| `UX-1A.6` | `P1-M1` | `UX` | `UX-1A` | Clarify parsing failure/edit UX: raw input visibility, manual correction path, and retry messaging. | `UX-1A.3`, `INP-1A.1` | failure-flow review | `defined` | `planned` | design-phase-b B4 |  |
| `UX-1A.7` | `P1-M1` | `UX` | `UX-1A` | Hide text/file AI input panels until workspace AI consent is acknowledged. | user feedback 2026-04-30 | controller regression test | `passing` | `accepted` | [app/views/parsing_sessions/index.html.erb](../app/views/parsing_sessions/index.html.erb), [test/controllers/parsing_sessions_controller_test.rb](../test/controllers/parsing_sessions_controller_test.rb) | Complete. |
| `UX-1A.8` | `P1-M1` | `UX` | `UX-1A` | Prevent parsing history time/action content from overlapping on narrow screens. | user feedback 2026-04-30 | responsive e2e regression | `passing` | `accepted` | [app/views/parsing_sessions/index.html.erb](../app/views/parsing_sessions/index.html.erb), [app/views/parsing_sessions/_parsing_session_card.html.erb](../app/views/parsing_sessions/_parsing_session_card.html.erb), [e2e/parsing_session.spec.ts](../e2e/parsing_session.spec.ts) | Complete. |
| `UX-1B.1` | `P1-M1` | `UX` | `UX-1B` | Remove mandatory review touchpoints from the import UX: completion toasts/actions go to ledger or repair queue, parsing history no longer uses "검토하기", and the primary path stays "upload/paste → ledger updated". | `REQ-1B.1`, `INP-1B.1`, `INP-1B.2` | mobile e2e + upload completion UX check | `defined` | `planned` | [ADR-0001](decisions/ADR-0001-auto-post-imports.md) | Do after auto-post and duplicate policy are safe. |
| `UX-1B.2` | `P1-M1` | `UX` | `UX-1B` | Surface image rows missing required fields in exactly three places: post-parse toast, notification dropdown/list, and transaction page repair banner/filter. | `INP-1B.3` | controller/job repair surfacing tests + existing E2E smoke | `passing` | `accepted` | [app/models/notification.rb](../app/models/notification.rb), [app/jobs/file_parsing_job.rb](../app/jobs/file_parsing_job.rb), [app/controllers/transactions_controller.rb](../app/controllers/transactions_controller.rb), [app/views/shared/_toast.html.erb](../app/views/shared/_toast.html.erb), [app/views/transactions/index.html.erb](../app/views/transactions/index.html.erb), [app/views/notifications/_dropdown.html.erb](../app/views/notifications/_dropdown.html.erb), [app/views/notifications/_list.html.erb](../app/views/notifications/_list.html.erb), [test/jobs/file_parsing_job_test.rb](../test/jobs/file_parsing_job_test.rb), [test/controllers/transactions_controller_test.rb](../test/controllers/transactions_controller_test.rb), [current/RUNTIME.md](current/RUNTIME.md) | Complete for surfacing. Clicking toast/notification opens transaction repair mode scoped to the source parsing session; the transaction page banner opens all open repair items. |
| `UX-1B.3` | `P1-M1` | `UX` | `UX-1B` | Build focused repair UI for incomplete import rows: show only rows needing date/merchant/amount, make missing cells inline-editable, and remove rows after promotion. | `INP-1B.3` | repair flow e2e | `passing` | `accepted` | [app/views/transactions/_import_repair_table.html.erb](../app/views/transactions/_import_repair_table.html.erb), [app/controllers/import_issues_controller.rb](../app/controllers/import_issues_controller.rb), [test/controllers/transactions_controller_test.rb](../test/controllers/transactions_controller_test.rb), [test/controllers/import_issues_controller_test.rb](../test/controllers/import_issues_controller_test.rb), [e2e/import_repair.spec.ts](../e2e/import_repair.spec.ts) | Complete. Repair mode now edits missing fields and handles duplicate repair decisions. |
| `UX-1B.4` | `P1-M1` | `UX` | `UX-1B` | Provide an import-level undo/recovery path that replaces review discard/rollback for auto-posted imports. | `INP-1B.1` | undo/recovery tests + user copy review | `defined` | `planned` | [ADR-0001](decisions/ADR-0001-auto-post-imports.md) | Required before deleting review routes. |
| `UX-1B.5` | `P1-M1` | `UX` | `UX-1B` | Remove review routes/controllers/views/status badges and update parsing history/detail pages after auto-post, repair, duplicate, and undo coverage land. | `UX-1B.1`, `UX-1B.4`, `INP-1B.4` | full test suite + dead-code scan | `defined` | `planned` | [ADR-0001](decisions/ADR-0001-auto-post-imports.md) | Dev latest is the compatibility baseline; no legacy pending-review migration required unless data exists. |
| `UX-1B.6` | `P1-M1` | `UX` | `UX-1B` | Observe founder/wife mobile web session through upload/paste → auto-posted ledger → exception repair, then record blockers as slices or decisions. | `UX-1B.1`, `UX-1B.2`, `UX-1B.3`, `UX-1B.4`, `UX-1B.5` | `ROAD-001` | `defined` | `planned` | [ADR-0001](decisions/ADR-0001-auto-post-imports.md) | This is the new P1-M1 human observation gate. |
| `OBS-1A.1` | `P1-M2` | `OBS` | `OBS-1A` | Define eval fixture policy for real Korean SMS, screenshots, privacy redaction, and expected labels. | `UX-1B.6` | `ROAD-002` | `defined` | `ready` | Q-001, Q-003 |  |
| `OBS-1A.2` | `P1-M2` | `OBS` | `OBS-1A` | Build eval harness for text parsing, image parsing, categorization, duplicate detection, and commit outcomes. | `OBS-1A.1` | eval command documented | `defined` | `planned` | design-phase-b B0 |  |
| `OBS-1A.3` | `P1-M2` | `OBS` | `OBS-1A` | Run baseline evals and publish results under `docs/evals/` with thresholds and known failures. | `OBS-1A.2` | eval result review | `defined` | `planned` | design-phase-b success criteria |  |
| `OBS-1A.4` | `P1-M2` | `OBS` | `OBS-1A` | Define runtime metrics contract for parsing success, duplicate rate, category hit rate, and commit success/failure. | `OBS-1A.1` | Q-003 resolution or ADR | `defined` | `planned` | Q-003 |  |
| `OBS-1A.5` | `P1-M2` | `OBS` | `OBS-1A` | Implement metrics storage/export/dashboard chosen by Q-003. | `OBS-1A.4` | metrics tests + docs | `defined` | `blocked` |  | Blocked on Q-003. |
| `INP-1A.1` | `P1-M2` | `INP` | `INP-1A` | Audit text/image parser confidence fields, source metadata, cancellation handling, and failure notifications against eval needs. | `OBS-1A.1` | targeted tests/docs | `defined` | `planned` | current runtime docs |  |
| `INP-1A.2` | `P1-M2` | `INP` | `INP-1A` | Benchmark non-Shinhan image samples against the current Vision prompt. | `OBS-1A.2` | eval threshold report | `defined` | `planned` | Q-001 |  |
| `INP-1A.3` | `P1-M2` | `INP` | `INP-1A` | Decide whether to productize multi-institution image support, keep it best-effort, or split institution prompts/router. | `INP-1A.2` | Q-001 decision / ADR | `defined` | `blocked` | Q-001 |  |
| `INP-1A.4` | `P3-M2` | `INP` | `INP-1A` | Implement the selected image expansion path if Q-001 accepts it. | `INP-1A.3` | AC extension + eval passing | `defined` | `blocked` |  | Blocked on Q-001. |
| `INP-1A.5` | `P3-M2` | `INP` | `INP-1A` | Add PWA camera upload / receipt-photo experiment if image eval and mobile observation justify it. | `INP-1A.3`, `UX-1B.6` | experiment review | `defined` | `deferred` | design-phase-a Phase A.5 |  |
| `INP-1A.6` | `P1-M1` | `INP` | `INP-1A` | Preserve image rows with missing required fields as visible incomplete parse items instead of silently dropping them. | user feedback 2026-04-30 | parser/job tests + review UI check | `passing` | `accepted` | [app/services/gemini_vision_parser_service.rb](../app/services/gemini_vision_parser_service.rb), [app/services/image_statement_parser.rb](../app/services/image_statement_parser.rb), [app/jobs/file_parsing_job.rb](../app/jobs/file_parsing_job.rb), [app/views/reviews/show.html.erb](../app/views/reviews/show.html.erb), [test/services/gemini_vision_parser_service_test.rb](../test/services/gemini_vision_parser_service_test.rb), [test/jobs/file_parsing_job_test.rb](../test/jobs/file_parsing_job_test.rb), [current/AI_PIPELINE.md](current/AI_PIPELINE.md), [current/RUNTIME.md](current/RUNTIME.md) | Complete. |
| `INP-1B.1` | `P1-M1` | `INP` | `INP-1B` | Auto-commit complete text/image parsed rows when parsing succeeds; move commit side effects such as `committed_by`, budget alerts, and completion notifications out of the review controller path. | `REQ-1B.1` | job/controller/model tests | `passing` | `accepted` | [app/models/parsing_session.rb](../app/models/parsing_session.rb), [app/jobs/ai_text_parsing_job.rb](../app/jobs/ai_text_parsing_job.rb), [app/jobs/file_parsing_job.rb](../app/jobs/file_parsing_job.rb), [app/services/budget_alert_service.rb](../app/services/budget_alert_service.rb), [test/models/parsing_session_test.rb](../test/models/parsing_session_test.rb), [test/jobs/ai_text_parsing_job_test.rb](../test/jobs/ai_text_parsing_job_test.rb), [test/jobs/file_parsing_job_test.rb](../test/jobs/file_parsing_job_test.rb), [test/controllers/reviews_controller_test.rb](../test/controllers/reviews_controller_test.rb), [current/RUNTIME.md](current/RUNTIME.md), [current/DATA_MODEL.md](current/DATA_MODEL.md) | Complete for rows with date/merchant/amount and no duplicate risk. Duplicate policy is now covered by `INP-1B.2`. |
| `INP-1B.2` | `P1-M1` | `INP` | `INP-1B` | Replace review-time duplicate blocking with an automatic duplicate policy: exact duplicates are skipped, ambiguous duplicates become repair issues instead of committed ledger rows. | `INP-1B.1` | duplicate detector + import job regression tests | `passing` | `accepted` | [app/services/import_duplicate_policy.rb](../app/services/import_duplicate_policy.rb), [app/models/import_issue.rb](../app/models/import_issue.rb), [db/migrate/20260502130000_add_duplicate_context_to_import_issues.rb](../db/migrate/20260502130000_add_duplicate_context_to_import_issues.rb), [db/migrate/20260502130100_enforce_import_issue_missing_fields_default.rb](../db/migrate/20260502130100_enforce_import_issue_missing_fields_default.rb), [app/jobs/ai_text_parsing_job.rb](../app/jobs/ai_text_parsing_job.rb), [app/jobs/file_parsing_job.rb](../app/jobs/file_parsing_job.rb), [test/jobs/ai_text_parsing_job_test.rb](../test/jobs/ai_text_parsing_job_test.rb), [test/jobs/file_parsing_job_test.rb](../test/jobs/file_parsing_job_test.rb), [test/models/import_issue_test.rb](../test/models/import_issue_test.rb), [current/RUNTIME.md](current/RUNTIME.md), [current/DATA_MODEL.md](current/DATA_MODEL.md) | Complete. Exact duplicates are skipped before ledger commit; ambiguous duplicates become `ImportIssue(issue_type: ambiguous_duplicate)`. |
| `INP-1B.3` | `P1-M1` | `INP` | `INP-1B` | Persist image rows missing date/merchant/amount as durable repair records instead of `ParsingSession#notes`, including visible values, `missing_fields`, source session/file, and status. | `INP-1A.6`, `REQ-1B.1` | migration/model/job tests + data model docs | `passing` | `accepted` | [app/models/import_issue.rb](../app/models/import_issue.rb), [db/migrate/20260501130000_create_import_issues.rb](../db/migrate/20260501130000_create_import_issues.rb), [app/jobs/file_parsing_job.rb](../app/jobs/file_parsing_job.rb), [app/views/reviews/show.html.erb](../app/views/reviews/show.html.erb), [app/views/parsing_sessions/show.html.erb](../app/views/parsing_sessions/show.html.erb), [test/models/import_issue_test.rb](../test/models/import_issue_test.rb), [test/jobs/file_parsing_job_test.rb](../test/jobs/file_parsing_job_test.rb), [test/controllers/reviews_controller_test.rb](../test/controllers/reviews_controller_test.rb), [test/controllers/parsing_sessions_controller_test.rb](../test/controllers/parsing_sessions_controller_test.rb), [current/DATA_MODEL.md](current/DATA_MODEL.md), [current/RUNTIME.md](current/RUNTIME.md), [current/AI_PIPELINE.md](current/AI_PIPELINE.md) | Complete. Legacy review and failed session detail show temporary notices so persisted issues are not hidden. |
| `INP-1B.4` | `P1-M1` | `INP` | `INP-1B` | Promote completed repair rows to committed transactions with category matching, duplicate policy, budget alert checks, notification resolution, and source metadata. | `INP-1B.3`, `UX-1B.3` | repair promotion tests | `passing` | `accepted` | [app/services/import_issue_resolution_service.rb](../app/services/import_issue_resolution_service.rb), [app/controllers/import_issues_controller.rb](../app/controllers/import_issues_controller.rb), [test/controllers/import_issues_controller_test.rb](../test/controllers/import_issues_controller_test.rb), [current/RUNTIME.md](current/RUNTIME.md), [current/DATA_MODEL.md](current/DATA_MODEL.md) | Complete. Promotions are exception commits, not review sessions. Exact duplicates are dismissed; ambiguous matches stay in the repair queue. |
| `CAT-1A.1` | `P1-M2` | `CAT` | `CAT-1A` | Measure text-path uncategorized rate and user correction rate. | `OBS-1A.4` | Q-002 evidence | `defined` | `planned` | Q-002 |  |
| `CAT-1A.2` | `P1-M2` | `CAT` | `CAT-1A` | Decide whether text path should gain Gemini category fallback. | `CAT-1A.1` | Q-002 decision / ADR | `defined` | `blocked` | Q-002 |  |
| `CAT-1A.3` | `P1-M2` | `CAT` | `CAT-1A` | Implement selected text categorization expansion, or record explicit no-change decision. | `CAT-1A.2` | AC-007 update if changed | `defined` | `blocked` |  | Blocked on Q-002. |
| `CAT-1A.4` | `P1-M2` | `CAT` | `CAT-1A` | Evaluate prompt-prefix/cache-friendly categorization and parser prompts if latency/cost data warrants it. | `OBS-1A.3` | ADR if adopted | `defined` | `planned` | [current/AI_PIPELINE.md](current/AI_PIPELINE.md) |  |
| `API-1A.1` | `P1-M3` | `API` | `API-1A` | Audit API key management UX: create, view prefix, revoke, scopes, docs, and test coverage. | `P0-M0` | API key UX review | `defined` | `planned` | AC-004, AC-012 |  |
| `API-1A.2` | `P1-M3` | `API` | `API-1A` | Decide and implement API rate limiting / abuse protection. | `API-1A.1` | tests + operations docs | `defined` | `planned` | design-phase-a Eng Review |  |
| `API-1A.3` | `P1-M3` | `API` | `API-1A` | Expose MCP write tool for existing API transaction creation, or document why REST write is enough. | `API-1A.1` | MCP tool smoke test | `defined` | `planned` | design-phase-b Phase C, current `mcp-server.json` |  |
| `API-1A.4` | `P2-M2` | `API` | `API-1A` | Add analytics aggregation endpoints for family/member comparisons, trends, budget, and recurring-payment summaries. | `INS-1A.2`, `OBS-1A.4` | API tests + docs | `defined` | `planned` | design-phase-a Phase C |  |
| `API-1A.5` | `P2-M2` | `API` | `API-1A` | Document BYOAI client recipes for ChatGPT/Claude/Gemini using API/MCP data safely. | `API-1A.3`, `API-1A.4` | docs review | `defined` | `planned` | "AI is brain, xef-scale is memory" principle |  |
| `INS-1A.1` | `P1-M1` | `INS` | `INS-1A` | Audit budget setting, progress display, 80%/100% alert behavior, and tests; add missing acceptance if needed. | `P0-M0` | budget setting/progress/alert tests | `passing` | `accepted` | [app/views/workspaces/settings.html.erb](../app/views/workspaces/settings.html.erb), [app/controllers/workspaces_controller.rb](../app/controllers/workspaces_controller.rb), [test/controllers/workspaces_controller_test.rb](../test/controllers/workspaces_controller_test.rb), [test/controllers/reviews_controller_test.rb](../test/controllers/reviews_controller_test.rb), [test/jobs/ai_text_parsing_job_test.rb](../test/jobs/ai_text_parsing_job_test.rb), [test/models/budget_test.rb](../test/models/budget_test.rb), [current/RUNTIME.md](current/RUNTIME.md) | Complete; budget alert dispatch now shared by legacy review commit and auto-post import finalization. |
| `INS-1A.2` | `P1-M1` | `INS` | `INS-1A` | Audit recurring-payment detection/list UX, false positives, and test coverage. | `P0-M0` | recurring detector/controller tests | `passing` | `accepted` | [app/services/recurring_payment_detector.rb](../app/services/recurring_payment_detector.rb), [app/views/dashboards/recurring.html.erb](../app/views/dashboards/recurring.html.erb), [test/services/recurring_payment_detector_test.rb](../test/services/recurring_payment_detector_test.rb), [test/controllers/dashboards_controller_test.rb](../test/controllers/dashboards_controller_test.rb), [current/RUNTIME.md](current/RUNTIME.md) | Complete. |
| `INS-1A.3` | `P1-M1` | `INS` | `INS-1A` | Improve mobile dashboard hierarchy: monthly total hero, category percentages, family-readable summaries. | `UX-1A.2` | controller summary cards + dashboard e2e | `passing` | `accepted` | [app/controllers/dashboards_controller.rb](../app/controllers/dashboards_controller.rb), [app/views/dashboards/monthly.html.erb](../app/views/dashboards/monthly.html.erb), [test/controllers/dashboards_controller_test.rb](../test/controllers/dashboards_controller_test.rb), [e2e/dashboard.spec.ts](../e2e/dashboard.spec.ts), [current/RUNTIME.md](current/RUNTIME.md) | `P1-M1` now waits on `UX-1B.6` observation evidence. |
| `INS-1A.5` | `P1-M1` | `INS` | `INS-1A` | Tighten recurring-payment detection so stale past subscriptions are excluded while one skipped month remains tolerated. | user feedback 2026-04-30, `INS-1A.2` | recurring detector regression tests | `passing` | `accepted` | [app/services/recurring_payment_detector.rb](../app/services/recurring_payment_detector.rb), [test/services/recurring_payment_detector_test.rb](../test/services/recurring_payment_detector_test.rb), [current/RUNTIME.md](current/RUNTIME.md) | Complete. |
| `INS-1A.4` | `P2-M2` | `INS` | `INS-1A` | Decide which insights belong in-app versus BYOAI endpoints; implement only stateful app-owned views. | `API-1A.4` | decision record | `defined` | `planned` | design-phase-a Phase C principle |  |
| `OPS-1A.1` | `P1-M4` | `OPS` | `OPS-1A` | Decide ActiveStorage blob retention/deletion after parsing complete/fail/discard/commit. | `INP-1A.1` | retention tests/docs | `defined` | `planned` | Q-007, current `needs audit` |  |
| `OPS-1A.2` | `P1-M4` | `OPS` | `OPS-1A` | Audit Solid Queue worker process in dev, CI, STG, PRD and document the source of truth. |  | operations doc update | `defined` | `planned` | [current/OPERATIONS.md](current/OPERATIONS.md) `needs audit` |  |
| `OPS-1A.3` | `P1-M4` | `OPS` | `OPS-1A` | Add Gemini usage/quota/rate-limit monitoring or an explicit no-monitoring decision. | `OBS-1A.4` | operations docs + tests if code | `defined` | `planned` | [current/OPERATIONS.md](current/OPERATIONS.md) |  |
| `OPS-1A.4` | `P1-M4` | `OPS` | `OPS-1A` | Reconcile `Transaction.source_type = import` with import rake tasks or mark it reserved with tests/docs. |  | data-model review | `defined` | `planned` | [current/DATA_MODEL.md](current/DATA_MODEL.md) `needs audit` |  |
| `OPS-1A.5` | `P1-M4` | `OPS` | `OPS-1A` | Decide whether `config/deploy.yml` / Kamal placeholders stay, move, or get deleted. |  | operations decision | `defined` | `planned` | [current/CODE_MAP.md](current/CODE_MAP.md) `needs audit` |  |
| `OPS-1A.6` | `P1-M4` | `OPS` | `OPS-1A` | Demote and guard the current `DatabaseBackupService` as development/import-only, with tests and docs for that limited contract. | `DEC-001` | unit tests + operations docs | `passing` | `accepted` | [app/services/database_backup_service.rb](../app/services/database_backup_service.rb), [test/services/database_backup_service_test.rb](../test/services/database_backup_service_test.rb), [current/OPERATIONS.md](current/OPERATIONS.md#db-백업--복구-상태) | Complete. |
| `OPS-1A.7` | `P1-M4` | `OPS` | `OPS-1A` | Implement a verified environment-aware SQLite backup/restore primitive for configured DB roles, using SQLite-safe backup/checkpoint and integrity checks. | `OPS-1A.6` | restore smoke test + docs | `passing` | `accepted` | [app/services/sqlite_backup_service.rb](../app/services/sqlite_backup_service.rb), [test/services/sqlite_backup_service_test.rb](../test/services/sqlite_backup_service_test.rb), [current/OPERATIONS.md](current/OPERATIONS.md#db-백업--복구-상태) | Complete. Storage/schedule policy remains Q-008. |
| `OPS-1A.8` | `P1-M4` | `OPS` | `OPS-1A` | Decide STG/PRD DB backup RPO/RTO, off-server storage, retention, encryption/access, and queue/cache/cable restore scope. | `DEC-001` | Q-008 decision / ADR | `defined` | `blocked` | Q-008 | Needs user/ops policy decision. |
| `OPS-1A.9` | `P1-M4` | `OPS` | `OPS-1A` | Wire the accepted STG/PRD backup schedule, durable storage, monitoring, and restore drill into ops/runbook. | `OPS-1A.8` | restore drill evidence + runbook | `defined` | `blocked` | Q-008 | Blocked on Q-008. |
| `BIZ-2A.1` | `P2-M1` | `BIZ` | `BIZ-2A` | Decide free / paid own-AI / BYOAI tier boundaries, workspace limits, data retention, ads, and API access. | P1 evidence | Q-006 decision | `defined` | `planned` | design-phase-b revenue model |  |
| `BIZ-2A.2` | `P2-M1` | `BIZ` | `BIZ-2A` | Spike billing provider choice: Stripe, Toss Payments, PortOne/Iamport, or manual invite-only billing. | `BIZ-2A.1` | Q-004 decision | `defined` | `planned` | design-phase-b Open Question 3 |  |
| `BIZ-2A.3` | `P2-M1` | `BIZ` | `BIZ-2A` | Implement billing subscription records, entitlement gates, and admin/support flows. | `BIZ-2A.2` | billing tests + operations docs | `defined` | `blocked` |  | Blocked on Q-004/Q-006. |
| `BIZ-2A.4` | `P2-M1` | `BIZ` | `BIZ-2A` | Implement tier limits for data history, workspaces, Vision parsing, API/MCP, and ads if accepted. | `BIZ-2A.3` | entitlement tests | `defined` | `blocked` |  | Blocked on Q-006. |
| `BIZ-2A.5` | `P2-M1` | `BIZ` | `BIZ-2A` | Add AI cost controls tied to entitlements and Gemini usage metrics. | `BIZ-2A.4`, `OPS-1A.3` | cost guard tests/docs | `defined` | `blocked` |  |  |
| `NTV-3A.1` | `P3-M1` | `NTV` | `NTV-3A` | Recheck Apple extension / share sheet / SMS constraints after platform updates and document decision. | P1 observation | Q-005 decision | `defined` | `deferred` | design-phase-b premise 8 |  |
| `NTV-3A.2` | `P3-M1` | `NTV` | `NTV-3A` | Spike Android SMS auto parsing feasibility, permissions, Play policy, privacy copy, and maintenance cost. | `NTV-3A.1` | native spike result | `defined` | `deferred` | design-phase-b Approach A |  |
| `NTV-3A.3` | `P3-M1` | `NTV` | `NTV-3A` | Spike iOS share extension / file-provider / camera capture path if web UX is insufficient. | `NTV-3A.1` | native spike result | `defined` | `deferred` | design-phase-b Open Question 5 |  |
| `NTV-3A.4` | `P3-M1` | `NTV` | `NTV-3A` | Build native client MVP only if Q-005 accepts an OS-integrated path. | `NTV-3A.2` or `NTV-3A.3` | native MVP acceptance | `defined` | `blocked` |  | Blocked on Q-005. |

## Dropped / Superseded Paths

| Slice | Source | Decision | Status | Notes |
|---|---|---|---|---|
| `DROP-1` | design-phase-a parser inventory | Restore Excel/PDF/CSV/HTML upload parsers and `ParserRouter`. | `dropped` | Current PRD explicitly scopes these out. Reintroduction requires ADR and PRD change. |
| `DROP-2` | design-phase-a institution parser list | Build 200+ financial SMS regex parser coverage. | `dropped` | Phase B selected LLM parsing instead; cheap classifier is only a future ADR candidate. |
| `DROP-3` | market alternatives | MyData/banking API direct integration. | `dropped` | Regulatory/cost constraint; out of scope in PRD. |
| `DROP-4` | design-phase-b BYOAI framing | Make BYOAI the main consumer onboarding path. | `dropped` | BYOAI remains power-user / paid-tier support path, not default UX. |

## Gates / Acceptance

- Product acceptance gates live in [06_ACCEPTANCE_TESTS.md](06_ACCEPTANCE_TESTS.md).
- Automated checks are listed in [current/TESTING.md](current/TESTING.md).
- Roadmap-only gates are defined in this document until they become product AC rows.
- A slice can be `landed` before its gate is `passing`.
- A milestone is `accepted` only when its required gates are `passing` or explicitly `waived`.

## Traceability

- Completed slices that affect product scope, architecture, runtime, operations, or delivery process should have a row in [09_TRACEABILITY_MATRIX.md](09_TRACEABILITY_MATRIX.md) or explicit evidence in this ledger.
- Link slices to the relevant Q / DEC / ADR, REQ / NFR, AC / TEST, and milestone.
- Do not use trace rows as a backlog. They are connection records for important paths.

## Dependencies

- Human observation: founder/wife mobile web session for P1-M1 after auto-post + exception repair flow lands.
- Sample data: redacted Korean SMS, app screenshots, Shinhan and non-Shinhan statements for P1-M2/P3-M2.
- Product decisions: Q-001 through Q-008 in [07_QUESTIONS_REGISTER.md](07_QUESTIONS_REGISTER.md).
- Billing provider and legal/privacy copy for P2.
- Platform policy review for P3 native/OS integrations.

## Open Risks

검증이 필요한 가정은 [03_RISK_SPIKES.md](03_RISK_SPIKES.md)로 승격한다.

Known risks:

- Non-Shinhan image parsing may underperform the current product promise if users upload arbitrary institutions.
- Metrics and billing decisions can overfit before real usage exists.
- Native app scope can balloon; keep P3 deferred until P1/P2 evidence exists.
- ActiveStorage retention and Gemini usage monitoring affect privacy/cost posture and should not remain `needs audit` indefinitely.
- Current DB backup helper is not a reliable STG/PRD backup/restore process; keep `OPS-1A.6` through `OPS-1A.9` visible until resolved.
- Auto-post imports can put parser mistakes directly into the ledger; do not remove review routes until import-level undo/recovery passes.

## Capacity / Timeline

- `P1-M1`: auto-post import transition (`REQ-1B`/`INP-1B`/`UX-1B`) plus one observation cycle; this is now a larger UX/data-flow change, not just small polish.
- `P1-M2`: eval harness + sample collection; time-box before expanding parser scope.
- `P1-M3/P1-M4`: hardening; can run in parallel after P1-M2 gates are defined.
- `P2`: do only after enough usage/adoption evidence exists.
- `P3`: deferred until web/BYOAI path proves insufficient.
