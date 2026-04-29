# 04 Implementation Plan

제품 gate, 기술 흐름, 구현 slice 상태를 한 곳에서 시퀀싱한다.

세부 tracking은 issue tracker와 PR이 담당한다. 이 문서는 roadmap / status ledger의 canonical view만 유지한다. 구현 단계의 얇은 문서 레이어([context/current-state.md](context/current-state.md), [current/](current/))에는 전체 roadmap inventory를 복제하지 않는다.

## Taxonomy

| Term | Meaning | Example ID | Notes |
|---|---|---|---|
| Milestone | 제품 / 사용자 관점의 delivery gate | `P0-M1` | "사용자가 어떤 상태를 얻는가"를 기준으로 정의 |
| Track | 기술 영역 또는 큰 구현 흐름 | `DOC` | docs, req, runtime, data, ops 같은 영역 |
| Phase | track 안의 구현 단계 | `DOC-1B` | 같은 track 안에서 순서가 있는 단계 |
| Slice / Task | 커밋 가능한 구현 단위 | `DOC-1B.1` | PR / commit / issue와 연결 가능한 크기 |
| Gate | 검증 / acceptance 기준 | `AC-012` / `TEST-018` | [06_ACCEPTANCE_TESTS.md](06_ACCEPTANCE_TESTS.md) 또는 테스트 위치로 연결 |
| Evidence | 완료를 뒷받침하는 근거 | PR, code, tests, current docs | 본문 복제 대신 링크 / ID로 남김 |

## Thin-doc Boundary

- `docs/04_IMPLEMENTATION_PLAN.md`가 roadmap / status ledger의 canonical 위치다.
- `docs/context/current-state.md`는 현재 milestone / track / phase / slice만 짧게 요약한다.
- `docs/current/`는 구현된 상태를 빠르게 찾는 navigation layer다. 미래 roadmap, phase inventory, 상세 backlog를 복제하지 않는다.
- Evidence는 code / test / PR / current doc 링크로 남기고, 구현 상세를 이 문서에 길게 복사하지 않는다.
- 완료된 slice라도 runtime, schema, operation, test command가 바뀌면 해당 current doc을 함께 갱신한다.

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

## Milestones

| Milestone | Product / user gate | Target date | Status | Gate | Evidence | Notes |
|---|---|---|---|---|---|---|
| `P0-M1` | Current product contract is traced to requirements, acceptance criteria, tests, and open gaps. | 2026-04-28 | `landed` | link review | `5cecb68`, `a434a35`, `c79e678` | Boilerplate structure and requirement traceability backfill landed on `dev`. |
| `P0-M2` | Roadmap/status taxonomy and maintenance-drift workflow are adopted without moving xef-scale canonical implementation docs. | 2026-04-29 | `landed` | link review + docs review | this change set; `git diff --check`; markdown link check | Latest boilerplate `24851cf` and `24b47f1` migration. |

## Tracks

| Track | Purpose | Active phase | Status | Notes |
|---|---|---|---|---|
| `DOC` | Documentation structure, roadmap ledger, generated docs, and agent guidance | `DOC-1B` | `landed` | Current migration track. |
| `REQ` | Product requirements, acceptance criteria, and traceability backfill | `REQ-1A` | `landed` | Backfilled from current PRD and implemented behavior. |
| `RUN` | Runtime/data/AI/operations current docs |  | `ready` | Update only when implementation changes. |

## Phases / Slices

| Slice | Milestone | Track | Phase | Goal | Depends | Gate | Gate status | Status | Evidence | Next |
|---|---|---|---|---|---|---|---|---|---|---|
| `DOC-1A.1` | `P0-M1` | `DOC` | `DOC-1A` | Adopt boilerplate document structure using xef-scale canonical paths. |  | link review | `passing` | `landed` | `5cecb68` | Keep wrappers thin; do not duplicate canonical docs. |
| `REQ-1A.1` | `P0-M1` | `REQ` | `REQ-1A` | Backfill product requirements, acceptance criteria, and traceability for implemented behavior. | `DOC-1A.1` | AC/Test trace review | `passing` | `landed` | `a434a35`, `c79e678`, [06_ACCEPTANCE_TESTS.md](06_ACCEPTANCE_TESTS.md), [09_TRACEABILITY_MATRIX.md](09_TRACEABILITY_MATRIX.md) | Resolve open gaps in Q-001, Q-002, Q-003 as separate slices. |
| `DOC-1B.1` | `P0-M2` | `DOC` | `DOC-1B` | Migrate to the updated roadmap/status taxonomy and maintenance drift workflow from boilerplate `24851cf` / `24b47f1`. | `DOC-1A.1` | link review + docs review | `passing` | `landed` | this change set; `git diff --check`; markdown link check | Publish through the standard review flow. |

## Gates / Acceptance

- Product acceptance gates live in [06_ACCEPTANCE_TESTS.md](06_ACCEPTANCE_TESTS.md).
- Automated checks are listed in [current/TESTING.md](current/TESTING.md).
- A slice can be `landed` before its gate is `passing`.
- A milestone is `accepted` only when its required gates are `passing` or explicitly `waived`.

## Traceability

- Completed slices that affect product scope, architecture, runtime, operations, or delivery process should have a row in [09_TRACEABILITY_MATRIX.md](09_TRACEABILITY_MATRIX.md) or explicit evidence in this ledger.
- Link slices to the relevant Q / DEC / ADR, REQ / NFR, AC / TEST, and milestone.
- Do not use trace rows as a backlog. They are connection records for important paths.

## Dependencies

- External teams/systems:
- Libraries/vendors:

## Open Risks

검증이 필요한 가정은 [03_RISK_SPIKES.md](03_RISK_SPIKES.md)로 승격한다.

## Capacity / Timeline

- 인원:
- 주당 가용 시간:
- 예상 완료:

## Migrating Existing Projects

Use this checklist when applying the taxonomy to a project that already has roadmap or status content scattered across documents.

1. Search existing docs for `milestone`, `phase`, `task`, `status`, `done`, `pending`, and project-specific roadmap words.
2. Map product / user-facing gates to Milestones.
3. Map technical streams to Tracks.
4. Map ordered implementation stages inside each track to Phases.
5. Map PR-sized or commit-sized units to Slices.
6. Map acceptance criteria, test scenarios, staging checks, or manual verification to Gates.
7. Create this ledger first, then trim duplicate roadmap/status inventories from `docs/context/current-state.md`, `docs/current/`, `AGENTS.md`, runtime docs, and architecture docs.
8. Split ambiguous `done` / `pending` states into implementation status and gate status. For example, a slice may be `landed` while its staging gate is `not_run`.
9. Preserve source anchors when moving information: path, commit, PR, ADR, DEC, Q, AC, TEST, or issue ID. If unknown, write `anchor missing`.
10. Keep project-specific historical reasoning in ADR / DEC / discovery / archive docs, not in the active status ledger.
