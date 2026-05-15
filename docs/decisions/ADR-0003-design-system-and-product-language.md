# ADR-0003: Design system & Product Language 채택

## Status

Accepted

## Date

2026-05-15

## Context

xef-scale은 가족·팀 공유 가계부 + AI 파싱(Gemini Flash / Vision) + 카테고리화 + 검토/커밋 워크플로우를 가진 Rails 8 + Tailwind + Hotwire 앱이다. 현재 UI는 다음 문제를 안고 있다 (`docs/discovery/2026-05-15-ui-redesign-plan.md 1장`):

- 시맨틱 토큰 부재 — Tailwind 팔레트 유틸리티(`text-gray-900`, `bg-indigo-600`)가 view에 인라인 산재.
- 컴포넌트 거버넌스 부재 — 같은 도메인 객체에 중복 partial (`transactions/_transaction_row` + `reviews/_transaction_row`).
- 카피 하드코딩 — 같은 의미("결제 내역"/"거래"/"내역")가 view마다 다름. `ko.yml`은 부재.
- 컬러 의미축 미분리 — `indigo-600`이 CTA·링크·활성 탭·hero 모두에 쓰여 "지금 누를 것"이 식별 불가.
- 다크 모드 부재 — `body class="bg-gray-50"` 하드코딩.
- 컴포넌트 명명 통일 부재 — 직군 간 같은 단어로 같은 대상을 부르는 어휘가 없음.

선행 디스커버리 노트가 두 경쟁 도메인 UI(토스·뱅크샐러드)를 해체분석해 16개 원칙(Claude P0~P15) + 12개 원칙(GPT) + BPL(뱅샐 Product Language)을 추출했고, 두 분석을 통합한 `2026-05-15-design-system-synthesis.md`가 xef-scale 채택 원칙 X1~X12와 토큰·컴포넌트 사전을 명시했다.

## Decision

xef-scale은 다음 4가지를 동시에 채택한다.

1. **xef-scale Design Principles X1~X12** — `2026-05-15-design-system-synthesis.md 3장`에 정의된 12개 원칙. 모든 UI 결정은 이 원칙에서 파생된다.
2. **시맨틱 디자인 토큰** — `synthesis.md 4장`에 정의된 컬러/타이포/간격/모션 토큰. Tailwind CSS의 `@theme` 블록과 `light-dark()`로 정의하며, `app/assets/stylesheets/application.tailwind.css`(또는 동등 진입점)를 단일 진실 원천으로 둔다. 컴포넌트는 *시맨틱* utility(`bg-surface`, `text-secondary`, `text-action`)만 사용하고 팔레트 utility(`bg-indigo-600`, `text-gray-900`)는 점진 제거한다.
3. **Product Language (xPL)** — `synthesis.md 6장`의 컴포넌트 사전. Scene(라우트) / Section / Card / Row / Chip / Sheet 5층 명명을 ERB partial 명에 일관 적용. 직군 간 같은 단어로 같은 대상을 부른다.
4. **컴포넌트 거버넌스 (X12; Toss P15에서 번역)** — 카탈로그에 없는 partial을 신설하려면 PR description에 "왜 기존 카탈로그로 못 푸는가" 1줄을 의무화한다. `_transaction_row` 같은 도메인 partial은 단일 출처를 유지하고 상태(`committed`/`pending_review`/`discarded`)는 conditional로 처리한다.

마이그레이션은 **Strangler Fig** 방식. 새 partial을 만들 때 기존 partial을 즉시 폐기하지 않고 페이지 단위로 점진 전환한다.

## Consequences

**긍정**
- 다크 모드 도입의 기반이 마련된다 (ADR-0008 종속).
- view 코드의 시각 일관성이 자동으로 보장된다.
- 직군 간 의사소통 비용 감소 (뱅샐 BPL 같은 코드 레벨 토큰화 시스템이 협업 비용을 줄인다는 보고가 있다 — 본 레포 규모에서는 효과가 비례한다고 단정하기 어렵고 기대 수준).
- 카피 변경이 `ko.yml` 한 곳에서 처리 (X10 종속).
- 신규 page 작성이 컴포넌트 조합으로 압축됨.

**부정**
- 초기 마이그레이션 비용 (Phase 1~7, `ui-redesign-plan.md 6장`).
- 기존 view를 점진 전환하는 동안 시각적 일관성이 한시 깨질 수 있음.
- `@theme` 블록 도입은 Tailwind 4를 전제. `package.json` 기준 `tailwindcss@^4.1.18` + `@tailwindcss/postcss` 도입 확인됨(2026-05-15). Phase 1에서 `@theme`·`light-dark()`·시맨틱 utility 생성 및 Rails 빌드 호환성을 실측 검증한다 (`docs/discovery/2026-05-15-design-system-open-questions.md Q1`).

**중립**
- ViewComponent 도입 여부는 본 ADR이 결정하지 않는다 — Phase 2 시작 전 별도 ADR.
- 일러스트 시스템은 본 ADR 범위 밖.

**테스트/문서 영향**
- `docs/code-map.md` 갱신 필요 (Phase별 PR에서).
- 시각 회귀 테스트 도입 권고 (Phase 2 이전 별도 디스커버리).

## Alternatives considered

1. **현 상태 유지** — 거부. 이미 다크 모드·검토함 IA 등이 이 기반 없이는 불가능.
2. **ViewComponent 전면 도입** — 거부 (현 시점). 마이그레이션 비용이 토큰·partial 표준화보다 훨씬 커 본 ADR의 범위를 넘는다. 별도 ADR로 재검토.
3. **외부 디자인 시스템 라이브러리 (e.g., Catalyst, shadcn 풍)** — 거부. 가계부 + 한국어 컨텍스트에 맞는 도메인 컴포넌트(검토함, 카테고리 출처 시각화 등)가 본 디스커버리에서 식별됨. 외부 라이브러리는 도메인 어휘를 강제하지 못함.
4. **Big Bang 마이그레이션** — 거부. 리뷰 불가능 + 회귀 위험. Strangler Fig 채택.

## Supersedes

없음.

## References

- 디스커버리: `docs/discovery/2026-05-15-design-system-synthesis.md`
- 디스커버리: `docs/discovery/2026-05-15-toss-ui-analysis.md`
- 디스커버리: `docs/discovery/2026-05-15-banksalad-ui-deconstruction.md`
- 실행 계획: `docs/discovery/2026-05-15-ui-redesign-plan.md`
- 관련 ADR: ADR-0004 (검토함 IA), ADR-0005 (광고 청정), ADR-0006 (의미축 분리), ADR-0007 (카테고리 출처), ADR-0008 (테마)
