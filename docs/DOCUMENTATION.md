# Documentation Policy

> Status: living policy · Owner: project lead · Last updated: 2026-04-28
>
> 시행 메커니즘: PR template (`.github/pull_request_template.md`) · Doc Freshness CI (`.github/workflows/doc-freshness.yml`) · Generated docs rake (`lib/tasks/docs.rake`) · thin docs SHA 헤더 (`docs/ai-pipeline.md`, `docs/categorization.md`).

xef-scale는 이미 운영에 가까운 **구현 단계** Rails 앱입니다. 이 문서는 코드 변경이 어떤 문서에 어떻게 반영돼야 하는지를 규정합니다. 목표는 문서 양을 늘리는 것이 아니라, 미래의 AI 구현 에이전트가 "지금 무엇이 사실인가"를 빠르고 정확하게 판단하도록 만드는 것입니다.

## Source-of-truth 우선순위

1. **코드, 테스트, 마이그레이션, `db/schema.rb`** — 구현된 동작의 절대적 권위.
2. **생성된 문서** (`docs/generated/*`) — 코드/스키마에서 자동 생성. *생성기*가 권위이며, 출력이 잘못되면 수동 편집 대신 생성기를 고친다. 생성 출력은 소스보다 lag 할 수 있으므로 충돌 시 1번이 이긴다.
3. **얇은 현재 상태 문서** (`docs/context/current-state.md`, `docs/architecture.md`, `docs/runtime.md`, `docs/data-model.md`, `docs/code-map.md`, `docs/categorization.md`, `docs/ai-pipeline.md`, `docs/testing.md`, `docs/operations.md`) — 코드의 *현재 모습*을 설명하지만 코드를 무효화하지 않는다.
4. **수락된 ADR** (`docs/decisions/ADR-*.md`) — 주요 결정의 *이유*. 새 동작에 맞춰 수정하지 않고 supersede 한다.
5. **에이전트 지시** (`AGENTS.md`, `CLAUDE.md`) — 에이전트가 따라야 할 운영 규칙.
6. **역사적 / 탐색 문서** (`docs/design/archive/`, `docs/design-phase-a.md`, `docs/design-phase-b.md`, `docs/discovery/`) — historical reasoning. 구현이 바뀌어도 *수정하지 않는다*. 새 ADR이 supersede 한다.

코드와 문서가 충돌하면 **코드가 이긴다**. 충돌을 발견했을 때의 규칙은 다음과 같다:
- 코드가 의도대로 동작하고 있다면 → thin docs(3번)을 같은 PR에서 패치한다.
- 코드가 ADR/PRD의 결정과 어긋난다면 → 코드를 고친다 (또는 새 ADR로 결정을 갱신한다).
- 긴 design 문서가 코드와 다르다면 → 그 design 문서는 이미 historical이다. 다시 쓰지 않는다.

## 구현 단계 이후의 thin layer 원칙

xef-scale은 이미 구현 단계에 들어왔다. 새 큰 단계가 시작되기 전까지는 **얇은 문서 레이어만** 유지한다.

- **유지 (구현 변경 때 갱신)**: `docs/context/current-state.md`, `docs/architecture.md`, `docs/runtime.md`, `docs/data-model.md`, `docs/code-map.md`, `docs/categorization.md`, `docs/ai-pipeline.md`, `docs/testing.md`, `docs/operations.md`, `PRD.md`, `README.md`.
- **유지 (결정 추가 시에만 갱신)**: `docs/decisions/ADR-*.md` — 새 ADR을 추가하거나 supersede 표시. 기존 ADR 본문은 수정하지 않는다.
- **동결 (historical, 수정 금지)**: `docs/design/archive/`, `docs/design-phase-a.md`, `docs/design-phase-b.md`, `docs/discovery/*`. 이 문서들은 *왜 이 방향으로 왔는지*를 보존하는 것이 가치이며, 현재 구현을 따라가게 만들면 historical 가치가 사라진다.
- **자동 생성**: `docs/generated/*`는 생성기가 만든다. 손으로 고치지 않는다.

`docs/discovery/`는 진행 중인 탐색 노트 자리다. 결론이 나면 `docs/decisions/`의 ADR로 옮기고, discovery 노트는 그대로 historical로 둔다.

## 변경 유형별 문서 업데이트

| 변경 유형 | 필수 문서 액션 |
|----------|---------------|
| 제품 스코프 변경 | `PRD.md` 업데이트, 아키텍처 영향이면 ADR 추가 |
| 런타임 흐름 변경 (입력→파싱→리뷰→커밋) | `docs/runtime.md`, 필요 시 `docs/context/current-state.md` |
| 모듈/파일 레이아웃 변경 | `docs/code-map.md` |
| DB/스키마/마이그레이션 변경 | `docs/data-model.md` |
| 파서/AI 파이프라인 변경 | `docs/ai-pipeline.md` 또는 `docs/categorization.md` |
| 지원 입력 경로 / 금융기관 변경 | `PRD.md`, `README.md`, `docs/context/current-state.md`, 관련 파이프라인 문서 |
| 테스트/린트/빌드 명령 변경 | `docs/testing.md` |
| 운영/배포 변경 | `docs/operations.md`, Claude 전용이면 `CLAUDE.md` |
| 주요 결정 수락 | `docs/decisions/`에 ADR 추가 또는 supersede |
| 진행 중 탐색 | `docs/discovery/`에 노트, 현재 문서에는 추가하지 않음 |
| 역사적 디자인 문서가 코드와 어긋남 | **수정하지 않는다.** 필요하면 새 ADR로 supersede |

## PR과 함께 가는 문서 변경

코드가 다음 중 하나를 바꾸면, **같은 PR에서** 매트릭스의 해당 thin doc을 함께 갱신한다.
- 런타임 동작
- 스키마 / 마이그레이션
- 모듈 / 파일 레이아웃
- 입력 경로 / 지원 금융기관
- 테스트 / 린트 / 빌드 / 배포 명령

문서를 잊었으면 PR 리뷰에서 막힌다. 큰 design 문서를 새로 쓰거나 historical 문서를 갱신하는 PR은 거의 항상 잘못된 방향이다 — 진짜 필요한 건 thin doc 패치이거나 새 ADR이다.

## 시행 메커니즘 (정책이 깨지지 않도록)

honor-system이 아닌 자동 보조 장치 4개로 정책을 받친다.

1. **PR template** (`.github/pull_request_template.md`) — Documentation impact 체크박스로 어떤 thin doc을 갱신했는지 명시 강제. `Regenerated docs/generated/*` 항목으로 generated docs 갱신도 추적.
2. **Doc Freshness CI** (`.github/workflows/doc-freshness.yml`) — PR이 `app/`, `app/models/`, `app/services|parsers|prompts/`, `app/jobs/`, `config/routes.rb`, `db/migrate/`, `db/schema.rb`를 건드렸는데 대응 thin doc / generated / ADR이 함께 변경되지 않으면 PR에 자동 코멘트로 누락 항목을 알린다. soft warning이며 머지를 막지는 않지만 가시성을 강제한다.
3. **Generated docs rake** (`lib/tasks/docs.rake`) — `bin/rake docs:generate`로 `docs/generated/routes.md`와 `docs/generated/schema.md`를 재생성. 라우트 / 스키마 변경 PR은 같은 PR에서 산출물도 commit 한다.
4. **Thin docs SHA 헤더** — `docs/ai-pipeline.md`, `docs/categorization.md` 두 stale-위험 문서에 "Last verified against code: `<SHA>` (`<date>`)" 헤더를 둔다. AI 호출 / 프롬프트 / 모델 / 카테고리 로직이 미세하게라도 바뀌면 같은 PR에서 SHA를 갱신한다. 헤더가 1개월 이상 같은 SHA에 머물러 있으면 staleness 경보로 본다.

## thin doc SHA 헤더 갱신 절차

```
# 변경된 파일이 AI/카테고리 로직이라면
sha=$(git rev-parse --short HEAD)
date=$(date -u +%Y-%m-%d)
# docs/ai-pipeline.md, docs/categorization.md 상단 헤더의 SHA / date 두 토큰을 수동 갱신
```

미세한 prompt wording 변경, 모델 버전 bump, fallback 순서 바꾸기 같은 것도 SHA 갱신 대상이다. SHA만 바꾸고 본문을 안 바꾼다면 그 자체가 "본문은 여전히 사실"이라는 검증 행위다.
