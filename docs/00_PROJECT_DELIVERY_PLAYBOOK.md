# 00 Project Delivery Playbook

xef-scale의 문서화/의사결정/전달 방식 요약.

## Workflow

```text
Question
 → Proposed Answer
  → Decision Register / ADR
   → PRD / HLD / Runbook / Acceptance Tests
    → Traceability Matrix
     → Retrospective
      → Extraction packet
       → external knowledge-base review / promotion
```

질문을 먼저 남기고, 답이 정해지면 결정으로 승격하고, 결정은 요구사항/설계/운영 문서에 반영하고, 연결은 Traceability로 추적한다. 회고에서 reusable 지식이 도출되면 extraction packet으로 정리하여 외부 knowledge base의 review / 승격 프로세스에 넘긴다. 승격 자체는 외부 knowledge base가 결정한다.

## Source-of-truth map

| Artefact | File |
|---|---|
| 열린 질문 | [07_QUESTIONS_REGISTER.md](07_QUESTIONS_REGISTER.md) |
| 가벼운 결정 | [08_DECISION_REGISTER.md](08_DECISION_REGISTER.md) |
| 중대한 결정 | [decisions/](decisions/) |
| 요구사항 | [01_PRD.md](01_PRD.md) |
| 상위 설계 | [02_HLD.md](02_HLD.md) |
| 가정 검증 | [03_RISK_SPIKES.md](03_RISK_SPIKES.md) |
| 작업 순서 | [04_IMPLEMENTATION_PLAN.md](04_IMPLEMENTATION_PLAN.md) |
| 운영 절차 | [05_RUNBOOK.md](05_RUNBOOK.md), [current/OPERATIONS.md](current/OPERATIONS.md) |
| 검증 기준 | [06_ACCEPTANCE_TESTS.md](06_ACCEPTANCE_TESTS.md) |
| 연결 매트릭스 | [09_TRACEABILITY_MATRIX.md](09_TRACEABILITY_MATRIX.md) |
| 회고 | [10_PROJECT_RETROSPECTIVE.md](10_PROJECT_RETROSPECTIVE.md) |

## ID conventions

```text
Q-001        Question
DEC-001      Decision Register entry
ADR-0001     Architecture Decision Record
REQ-001      Requirement
NFR-001      Non-functional requirement
AC-001       Acceptance criterion
TEST-001     Test
SPIKE-001    Risk spike
TASK-001     Implementation task
TRACE-001    Traceability row
```

## Implementation-stage docs

구현 작업의 첫 read는 [context/current-state.md](context/current-state.md)다. 세부 현재 구현 문서는 [current/](current/) 아래에 있다.

- `docs/current/`는 현재 구현 상태를 빠르게 찾기 위한 얇은 navigation docs다.
- numbered 문서(`01_PRD` ~ `10_RETROSPECTIVE`)는 project delivery artifacts다.
- [discovery/](discovery/)와 [design/archive/](design/archive/)는 역사/탐색 기록이며 현재 구현의 권위가 아니다.
- [generated/](generated/)는 코드/스키마에서 파생된 reference이며 손으로 편집하지 않는다.

상세 정책은 [DOCUMENTATION.md](DOCUMENTATION.md)와 [../AGENTS.md](../AGENTS.md)를 따른다.

## Extraction

회고에서 재사용 가능한 지식이 도출되면 [templates/EXTRACTION_TEMPLATE.md](templates/EXTRACTION_TEMPLATE.md)을 사용한다.

Extraction packet의 모든 row는 candidate다. 실제 promotion은 외부 knowledge base의 review / ingestion 프로세스가 결정한다.
