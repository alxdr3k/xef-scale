# 09 Traceability Matrix

Question ↔ Decision ↔ Requirement ↔ Acceptance/Test ↔ Task 연결.

## Matrix

| TRACE-ID | Question | Decision / ADR | Requirement | AC / Test | Task | Notes |
|---|---|---|---|---|---|---|
| TRACE-001 |  |  |  |  |  |  |

## Invariants

- 모든 `must` requirement는 최소 한 개의 acceptance criterion을 가져야 한다.
- 모든 accepted DEC/ADR은 영향을 받는 requirement, HLD, runbook, current doc 중 하나 이상을 명시한다.
- 제품 스코프, 아키텍처, 런타임, 운영 동작을 바꾸는 multi-PR task는 trace row를 가진다.

## Gaps

- 기존 `docs/design-phase-*.md`의 모든 내용을 기계적으로 backfill하지 않는다. 새 변경이 필요한 항목만 추적한다.
