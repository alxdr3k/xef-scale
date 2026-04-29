# Documentation Policy

> Status: living policy · Owner: project lead · Last updated: 2026-04-28
>
> Enforcement: PR template (`.github/pull_request_template.md`) · Doc Freshness CI (`.github/workflows/doc-freshness.yml`) · generated docs rake (`lib/tasks/docs.rake`) · thin docs SHA headers (`docs/current/AI_PIPELINE.md`, `docs/current/CATEGORIZATION.md`).

xef-scale는 이미 운영에 가까운 구현 단계 Rails 앱입니다. 이 문서는 코드 변경이 어떤 문서에 어떻게 반영돼야 하는지를 규정합니다. 목표는 문서 양을 늘리는 것이 아니라, 미래의 AI 구현 에이전트가 "지금 무엇이 사실인가"를 빠르고 정확하게 판단하도록 만드는 것입니다.

## Source-of-truth hierarchy

1. **Code, tests, migrations, `db/schema.rb`** — implemented behavior.
2. **Generated docs** (`docs/generated/*`) — derived from code/schema. Fix the generator, not generated output.
3. **Roadmap / status ledger** (`docs/04_IMPLEMENTATION_PLAN.md`) — milestone, track, phase, slice, gate, evidence, and next work.
4. **Current implementation docs** (`docs/context/current-state.md`, `docs/current/*`) — thin implementation-state navigation docs.
5. **Project delivery docs** (`docs/01_PRD.md`, `docs/02_HLD.md`, `docs/05_RUNBOOK.md`, `docs/06_ACCEPTANCE_TESTS.md`) — product scope, high-level design, operations, acceptance criteria.
6. **Decision records** (`docs/08_DECISION_REGISTER.md`, `docs/decisions/ADR-*.md`) — accepted rationale. Supersede; do not rewrite history.
7. **Agent instructions** (`AGENTS.md`, `CLAUDE.md`) — operating rules for coding agents.
8. **Discovery and archive** (`docs/discovery/`, `docs/design/archive/`, `docs/design-phase-*.md`) — history, not current authority.

코드와 문서가 충돌하면 코드가 이긴다. 코드가 의도대로라면 current docs를 패치하고, 코드가 product/ADR 결정과 어긋난다면 코드를 고치거나 새 결정으로 갱신한다.

## Canonical paths

| Concern | Canonical path |
|---|---|
| Product scope | `docs/01_PRD.md` |
| High-level design | `docs/02_HLD.md` |
| Roadmap / status ledger | `docs/04_IMPLEMENTATION_PLAN.md` |
| Runtime flow | `docs/current/RUNTIME.md` |
| Code map | `docs/current/CODE_MAP.md` |
| Data model | `docs/current/DATA_MODEL.md` |
| AI pipeline | `docs/current/AI_PIPELINE.md` |
| Categorization | `docs/current/CATEGORIZATION.md` |
| Testing commands | `docs/current/TESTING.md` |
| Operations | `docs/current/OPERATIONS.md`, `docs/05_RUNBOOK.md` |
| Generated routes/schema | `docs/generated/*` |
| ADRs | `docs/decisions/` |

The old flat paths (`PRD.md`, `docs/runtime.md`, `docs/code-map.md`, etc.) are redirect wrappers only. Do not edit wrappers for substantive changes.

## What to update when

| Change type | Required doc action |
|---|---|
| Product scope changes | update `docs/01_PRD.md`; add DEC/ADR if needed |
| Architecture changes | update `docs/02_HLD.md`; add/supersede ADR |
| Roadmap taxonomy or slice status changes | update `docs/04_IMPLEMENTATION_PLAN.md` |
| Active milestone / track / phase / slice changes | update `docs/context/current-state.md` |
| Gate definition or acceptance status changes | update `docs/06_ACCEPTANCE_TESTS.md` |
| Runtime behavior changes | update `docs/current/RUNTIME.md`; update `docs/context/current-state.md` if the summary changes |
| Module/file layout changes | update `docs/current/CODE_MAP.md` |
| DB/schema/data model changes | update `docs/current/DATA_MODEL.md`; run `bin/rake docs:generate:schema` |
| Route changes | run `bin/rake docs:generate:routes`; update current docs if behavior changed |
| AI/parser/categorization changes | update `docs/current/AI_PIPELINE.md` or `docs/current/CATEGORIZATION.md`; update SHA header |
| Input surface / supported institution changes | update `docs/01_PRD.md`, `README.md`, `docs/context/current-state.md`, and relevant current docs |
| Test/lint/build command changes | update `docs/current/TESTING.md` |
| Operational/env/deployment changes | update `docs/current/OPERATIONS.md` or `docs/05_RUNBOOK.md`; Claude-only safety rules stay in `CLAUDE.md` |
| New open question | add row to `docs/07_QUESTIONS_REGISTER.md` |
| Lightweight accepted decision | add entry to `docs/08_DECISION_REGISTER.md` |
| Major accepted decision | add ADR under `docs/decisions/` |
| Cross-document impact | update `docs/09_TRACEABILITY_MATRIX.md` |
| Historical exploration | put under `docs/discovery/` or `docs/design/archive/`; do not make it current authority |
| Milestone completion | update `docs/04_IMPLEMENTATION_PLAN.md`, `docs/context/current-state.md`, `docs/09_TRACEABILITY_MATRIX.md`, and `docs/10_PROJECT_RETROSPECTIVE.md` |

## Roadmap / Status Migration

When adopting updated boilerplate roadmap taxonomy in this existing project:

1. Map product/user-facing delivery gates to milestones.
2. Map technical streams to tracks.
3. Map ordered implementation stages inside each track to phases.
4. Map PR-sized or commit-sized work to slices.
5. Map acceptance criteria, automated tests, staging checks, and manual verification to gates.
6. Split ambiguous `done` / `pending` language into implementation status (`planned`, `landed`, `accepted`, etc.) and gate status (`defined`, `not_run`, `passing`, etc.).
7. Keep the canonical inventory in `docs/04_IMPLEMENTATION_PLAN.md`; do not duplicate full roadmap inventory in `docs/context/current-state.md`, `docs/current/`, runtime docs, architecture docs, or agent instructions.
8. Preserve source anchors when moving status: path, commit, PR, ADR, DEC, Q, AC, TEST, or issue ID. If unknown, write `anchor missing`.

## Enforcement

1. **PR template** requires documentation impact checkboxes.
2. **Doc Freshness CI** comments when code paths change without matching roadmap/status, acceptance gate, current/generated, or decision docs.
3. **Generated docs rake** regenerates `docs/generated/routes.md` and `docs/generated/schema.md`.
4. **SHA freshness headers** on `docs/current/AI_PIPELINE.md` and `docs/current/CATEGORIZATION.md` mark the code revision they were verified against.

## SHA freshness headers

When AI call paths, prompts, model lists, fallback order, parser behavior, or categorization logic changes:

```bash
sha=$(git rev-parse --short HEAD)
date=$(date -u +%Y-%m-%d)
```

Update the relevant header in `docs/current/AI_PIPELINE.md` or `docs/current/CATEGORIZATION.md`. Updating only the header means "the body was rechecked and is still true."
