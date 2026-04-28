# 06 Acceptance Tests

요구사항이 만족되었는지 검증하는 기준.

검증 명령은 [current/TESTING.md](current/TESTING.md)가 canonical이다. 이 문서는 요구사항과 scenario/test ID의 연결을 관리한다.

## Criteria

| ID | REQ/NFR | Scenario | Verification | Status |
|---|---|---|---|---|
| AC-001 | REQ-001 | Given ... When ... Then ... | manual / automated TEST-001 | pending |

## Tests

| ID | Name | Location | Covers |
|---|---|---|---|
| TEST-001 |  | `test/...` | AC-001 |

## Definition of Done

- 모든 `must` requirement는 최소 한 개의 acceptance criterion을 가진다.
- 모든 accepted criterion은 named manual check 또는 automated test로 검증된다.
- 운영상 중요한 시나리오는 [05_RUNBOOK.md](05_RUNBOOK.md) 또는 [current/OPERATIONS.md](current/OPERATIONS.md)에 연결된다.
- Traceability row는 [09_TRACEABILITY_MATRIX.md](09_TRACEABILITY_MATRIX.md)에 갱신된다.
