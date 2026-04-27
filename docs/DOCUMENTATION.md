# Documentation Policy

xef-scale는 구현 단계의 Rails 앱입니다. 이 문서는 변경된 동작·스코프·결정이 어떤 문서에 반영돼야 하는지를 규정합니다. 목표는 문서 양을 늘리는 것이 아니라, 미래의 AI 구현 에이전트가 "지금 무엇이 사실인가"를 빠르고 정확하게 판단하도록 만드는 것입니다.

## Source-of-truth 우선순위

1. 코드, 테스트, 마이그레이션, 생성된 스키마 (`db/schema.rb`)
2. 얇은 현재 상태 문서 (`docs/context/current-state.md`, `docs/runtime.md`, `docs/data-model.md`, `docs/code-map.md`, `docs/categorization.md`, `docs/ai-pipeline.md` 등)
3. 수락된 결정 (`docs/decisions/ADR-*.md`)
4. 디스커버리 / 역사적 설계 노트 (`docs/discovery/`, `docs/design/archive/`)
5. 에이전트 지시 파일 (`AGENTS.md`, `CLAUDE.md`)

## 규칙

- 코드·테스트·마이그레이션은 **구현된 동작**의 권위 있는 출처입니다.
- 현재 상태 문서는 코드를 *설명*할 뿐 코드를 **무효화하지 않습니다**.
- ADR은 주요 결정의 *이유*를 기록합니다.
- 수락된 ADR은 새 동작을 반영하기 위해 *수정하지 않습니다*. 새 ADR을 만들어 이전 ADR을 supersede 합니다.
- `docs/design/archive/`의 역사적 설계 노트와 `docs/design-phase-a.md`, `docs/design-phase-b.md`는 **역사**이며 현재 권위가 아닙니다.
- 구현이 바뀔 때마다 긴 디스커버리/디자인 문서를 갱신하지 마세요. 얇은 현재 문서에만 패치를 적용합니다.
- 가능한 곳에서는 코드에서 자동 생성된 문서(`docs/generated/`)를 선호합니다.
- 코드가 동작·스키마·런타임을 바꾸면, **같은 PR에서** 관련 얇은 문서를 갱신합니다.

## 변경 유형별 문서 업데이트

| 변경 유형 | 필수 문서 액션 |
|----------|---------------|
| 제품 스코프 변경 | `PRD.md` 업데이트, 아키텍처 영향이면 ADR 추가 |
| 런타임 흐름 변경 (입력→파싱→리뷰→커밋) | `docs/runtime.md` |
| 모듈/파일 레이아웃 변경 | `docs/code-map.md` |
| DB/스키마/마이그레이션 변경 | `docs/data-model.md` |
| 파서/AI 파이프라인 변경 | `docs/ai-pipeline.md` 또는 `docs/categorization.md` |
| 지원 입력 경로 / 금융기관 변경 | `PRD.md`, `README.md`, `docs/context/current-state.md`, 관련 파이프라인 문서 |
| 테스트/린트/빌드 명령 변경 | `docs/testing.md` |
| 운영/배포 변경 | `docs/operations.md`, Claude 전용이면 `CLAUDE.md` |
| 주요 결정 수락 | `docs/decisions/`에 ADR 추가 또는 supersede |
| 진행 중 탐색 | `docs/discovery/`에 노트, 현재 문서에는 추가하지 않음 |

## 작은 패치를 선호하세요

긴 디자인 문서를 다시 쓰는 것보다, 얇은 현재 상태 문서에 작은 패치를 다는 것이 낫습니다. 현재 상태 문서가 더 이상 사실이 아닐 때만 갱신하고, 탐색 메모는 `docs/discovery/`에 둡니다.
