# ADR-0008: 라이트 우선, 다크 동등 지원

## Status

Accepted

## Date

2026-05-15

## Context

토스(분석 P4 Dark-first)와 뱅크샐러드(분석 1.1) 모두 **다크 우선** 시각 시스템을 채택했다. 두 분석에서 다크 우선의 근거:

- 금융 데이터의 부담감(스트레스 컬러) 감소.
- 콘텐츠 카드의 elevation 표현이 명도 차로 가능.
- 모바일 주 사용 시간대(밤·새벽)에 시각 부담 ↓.

xef-scale의 컨텍스트는 다음 점에서 다르다:

- 주 사용 패턴은 **검토 작업** — `pending_review` 거래의 가맹점·금액·카테고리를 *읽고 정정*하는 텍스트 중심 작업. 텍스트 가독성은 라이트가 일반적으로 유리.
- 데스크탑·태블릿 사용 비중 ↑ (가족 공유 워크스페이스에서 정기 정리 작업).
- 명세서 스크린샷(ProcessedFile)이 라이트 톤이 많음 — UI가 라이트이면 미리보기와 톤 일관.
- 토스/뱅샐의 시각 모방을 회피하는 디자인 결정(`synthesis.md 2.4`)이기도 함.

그러나 다크 모드를 *지원하지 않는 것*은 별개 문제다. OS 다크 모드 사용자, 야간 사용 패턴, 접근성 요구가 모두 존재한다. 현재 코드(`application.html.erb`의 `class="bg-gray-50"` 하드코딩)는 다크 모드 자체가 불가능.

## Decision

**xef-scale은 라이트 우선 + 다크 동등 지원**으로 간다.

세부 결정:

1. **라이트가 기본 모드** (default `auto`로 OS 설정 따름. OS 미지원 시 라이트 fallback).
2. **다크 모드를 동등 지원** — 모든 토큰은 `light-dark()` CSS 함수로 라이트/다크 페어 정의 (ADR-0006의 토큰 시스템과 짝).
   - 한쪽만 정의하는 토큰 금지.
   - 다크 모드에서 명도 대비를 *별도 검증* (단순 색 반전이 아니라 다크 컨텍스트에서 컨트라스트 4.5:1 보장).
3. **사용자 설정으로 강제 토글 가능** — 값 도메인은 `auto | light | dark` 3종으로 고정. 저장 위치는 두 옵션 중 후속 ADR에서 선택한다 (현재 코드 사실: `UserSetting` 모델은 존재하지 않으며 사용자 설정은 `User#settings` JSON 컬럼에 저장된다, `serialize :settings, coder: JSON`).
   - 옵션 A (기존 패턴 유지): `current_user.settings["theme"]`.
   - 옵션 B (전용 컬럼): `users.theme:string` 추가.
   - 본 ADR은 *값 도메인과 토글 가능성*만 결정한다. 저장 매체는 `docs/discovery/2026-05-15-design-system-open-questions.md Q4` 후속 ADR (ADR-0010 후보)에서 확정.
   - "내 계정" 카드(ADR-0004 더보기 탭)에 화면 테마 SwitchRow.
   - `<html>` 태그에 `data-theme` 속성 부여, Stimulus `theme_controller`로 토글.
4. **컴포넌트는 토큰만 참조** — `bg-gray-50`, `text-gray-900` 같은 팔레트 utility 금지. `bg-surface`, `text-primary` 같은 시맨틱 utility만 사용.
5. **다크 모드 도입 단계는 Phase 5** (`ui-redesign-plan.md 6장`). Phase 1~4는 라이트만 마이그레이션, Phase 5에서 다크 페어 검증·도입.

## Consequences

**긍정**
- OS 다크 모드 사용자 지원.
- 토스·뱅샐의 다크 우선 시각 모방을 자동 회피 → 트레이드드레스 거리 확보.
- 검토 작업의 텍스트 가독성 우선 — 사용자 실수 ↓.
- 라이트와 다크 페어가 *처음부터* 토큰 시스템에 박혀 미래 변경 비용 ↓.

**부정**
- 다크 모드를 *동등하게* 지원하려면 모든 토큰의 페어 검증이 필요 — Phase 5 비용.
- 시각 회귀 테스트가 라이트·다크 양쪽에서 통과해야 함.
- 한쪽 모드에서만 발견되는 컨트라스트 회귀 위험.

**완화**
- Phase 5에서 자동화된 컨트라스트 감사 (axe-core 등).
- `light-dark()` 토큰을 강제 — 한쪽 누락 시 lint 또는 PR review로 차단.
- 다크 페어 우선순위는 *읽기 가능성* > *미감*.

**테스트/문서 영향**
- 시각 회귀 테스트가 라이트·다크 양쪽 스냅샷 (Phase 5).
- `docs/code-map.md`에 테마 저장 위치 (`User#settings["theme"]` 또는 `users.theme` 컬럼, 후속 ADR로 결정) 명시.
- `docs/runtime.md`에 테마 토글 컨트롤러 명시.

## Alternatives considered

1. **다크 우선 (토스·뱅샐 추종)** — 거부. 검토 작업의 텍스트 가독성, 명세서 미리보기 톤 일관, 시각 모방 회피를 종합하면 라이트가 더 맞음.
2. **라이트 전용 (다크 미지원)** — 거부. OS 다크 모드 사용자·야간 사용·접근성 요구 무시.
3. **다크와 라이트를 *비대칭* 지원** (예: 라이트만 검토 가능) — 거부. "동등" 지원이 디자인 시스템의 일관성 보장.
4. **테마 자동 전환 (시간대 기반)** — 거부. 예측 불가능한 자동 변경은 사용자 통제 박탈. OS 설정 추종(`auto`)으로 충분.

## Supersedes

없음.

## References

- 디스커버리: `docs/discovery/2026-05-15-design-system-synthesis.md` (4.1, 2.4)
- 디스커버리: `docs/discovery/2026-05-15-toss-ui-analysis.md` (P4 보정)
- 디스커버리: `docs/discovery/2026-05-15-banksalad-ui-deconstruction.md` (1.1)
- 디스커버리: `docs/discovery/2026-05-15-ui-redesign-plan.md` (5.3, Phase 5)
- 관련 ADR: ADR-0003, ADR-0006
- 코드: `app/views/layouts/application.html.erb`, `app/models/user.rb` (`serialize :settings, coder: JSON`), `app/controllers/user_settings_controller.rb`
