# ADR-0006: CTA와 시맨틱 컬러 축의 분리

## Status

Proposed

## Date

2026-05-15

## Context

토스(분석 P5)와 뱅크샐러드(분석 P1)는 모두 **단일 강조색**으로 CTA·링크·활성 탭·긍정·인사이트를 모두 표시한다 (토스 = 액션 블루, 뱅샐 = 민트). 이는 강한 시각 일관성을 만들지만, 두 부작용이 있다:

1. **사용자가 "지금 누를 것"과 "수입/긍정 표시"를 색으로 구분 못함** — 토스에서 액션 블루와 하락 블루가 같은 톤이라 발생하는 혼동과 동일.
2. **광고/추천에 같은 강조색이 재사용되면 dark pattern으로 작동** — 뱅샐 P10 사례. 사용자는 광고를 절약 인사이트로 오인.

xef-scale 현재 코드는 **`indigo-600`을 CTA(`bg-indigo-600`)·링크·활성 탭·hero 그라데이션 모두에 사용** 한다(`app/views/layouts/_navbar.html.erb`, `app/views/dashboards/monthly.html.erb`). 같은 함정을 따라가고 있다.

하지만 xef-scale은 ADR-0005에 따라 **광고가 없다**. 단일 강조색에 갇힐 외부 압력이 없다. 이 자유도를 활용해 의미축을 분리할 수 있다.

## Decision

**xef-scale은 컬러 의미축을 5개로 분리한다**. 각 토큰은 단 하나의 의미만 담당한다.

| 토큰 | 의미 | 사용처 |
|---|---|---|
| `color-action` | "지금 누르세요" (CTA) | 1차 CTA, 활성 탭, 링크 |
| `color-positive` | 수입·환급·달성 | TransactionRow income amount, 절약 표시 |
| `color-warning` | 검토 대기·주의 | `pending_review` 거래의 dot, 검토함 badge |
| `color-info` | 중립 정보·AI 보조 | `duplicate` pending, 정보 alert |
| `color-danger` | 비가역·시스템 에러 | 삭제 confirm, error alert |

세부 규칙:
- `color-action`은 *액션 블루/인디고 계열* (CTA 식별성). `color-positive`는 *그린 계열*. `color-warning`은 *앰버 계열*. `color-info`는 *시안/스카이 계열*. `color-danger`는 *레드 계열*.
- **금액 표시**: 지출은 `text-primary`(중립, 빨강 금지), 수입은 `text-positive`. 금액에 `text-action` 사용 금지.
- **AI 출력물**은 별도 보라 계열(`color-ai`)로 격리. CTA·정보·긍정 어느 축에도 속하지 않음. ADR-0007와 함께 적용.
- **카테고리 chart 팔레트**는 위 5축과 모두 톤 분리. 채도·명도로 구분.
- 토큰은 `light-dark()` CSS 함수로 라이트/다크 페어 정의 (ADR-0008).

토큰 전체 정의는 `docs/discovery/2026-05-15-design-system-synthesis.md 4.1`을 1차 출처로 한다. `app/assets/stylesheets/application.tailwind.css`에 `@theme` 블록으로 코드화.

## Consequences

**긍정**
- 사용자가 화면에서 "지금 누를 것"을 1초 안에 식별.
- 수입 표시(`positive`)와 CTA(`action`)가 헷갈리지 않음.
- 미해결 검토(`warning`)와 일반 액션(`action`)이 시각적으로 구분 — 검토 압력이 더 명확.
- AI 출력물(`ai`) 격리로 사용자가 "이건 AI 추정"을 즉시 인지.
- 광고 도입(ADR-0005 supersede) 시에도 시맨틱 축은 보호됨.

**부정**
- 색이 5개로 늘어 시각적 *조화* 부담. 디자이너가 각 축의 톤을 정확히 분리하지 않으면 산만해 보일 수 있음.
- 접근성: 5축 모두 WCAG AA(컨트라스트 4.5:1) 통과 검증 필요.

**완화**
- 토큰별 hue·채도·명도 가이드 명시 (위 표).
- Phase 5에서 컨트라스트 감사 게이트.
- 색맹/저시력: 모든 상태를 색 + 아이콘 + 라벨 중 둘 이상으로 표현.

**테스트/문서 영향**
- 시각 회귀 테스트가 토큰 변경 시 의도된 변경을 통과시키도록 갱신.
- `docs/code-map.md`에 토큰 위치 명시.

## Alternatives considered

1. **현 상태 유지 (단일 인디고)** — 거부. 위 컨텍스트의 두 부작용을 그대로 안음. 사용자가 CTA·hero·링크·활성 탭을 색으로 구분 못함.
2. **2축 분리 (action / semantic)** — 거부. `positive`/`warning`/`info`/`danger`가 한 토큰에 묶이면 검토 대기와 시스템 에러가 같은 색이 되어 부적절.
3. **4축 (warning과 info 통합)** — 거부. `pending_review`(warning)와 `duplicate`(info)는 사용자 행동이 다름 — 검토 대기는 *작업 큐*, 중복은 *결정 요구*. 톤 분리가 필요.
4. **6+ 축** — 거부. 시각 조화 부담 vs 의미 분리 효용에서 5축이 균형점.

## Supersedes

없음.

## References

- 디스커버리: `docs/discovery/2026-05-15-design-system-synthesis.md` (4.1, X5)
- 디스커버리: `docs/discovery/2026-05-15-toss-ui-analysis.md` (P5 보정)
- 디스커버리: `docs/discovery/2026-05-15-banksalad-ui-deconstruction.md` (P1, P10)
- 관련 ADR: ADR-0003 (Design system), ADR-0005 (광고 청정), ADR-0007 (카테고리 출처), ADR-0008 (다크 모드)
