# Decisions

xef-scale의 수락된 구현·아키텍처 결정 기록(ADR).

## 규칙

- 끝없는 논쟁을 현재 상태 문서에 누적하지 말 것. 결정은 ADR로 분리.
- 수락된 ADR은 새 동작을 반영하기 위해 *수정하지 않는다*. 결정이 바뀌면 새 ADR을 만들어 `Superseded by`로 연결.
- 디스커버리 노트는 ADR로 *링크*할 수 있지만, ADR이 결정의 권위 있는 출처다.
- 모든 ADR은 `ADR-XXXX-제목.md` 형식. 번호는 추가되는 순서대로.

## 작성 방법

`ADR-TEMPLATE.md`를 복사해 채운다. 큰 결정에만 사용 (예: 입력 경로 변경, 외부 모델/저장소 변경, 멀티테넌트 경계 변경, AI 호출 정책 변경).

## 현재 ADR

- [ADR-0001](ADR-0001-defer-pundit-adoption.md) — Pundit 채택을 보류하고 커스텀 권한 패턴을 유지한다 (Accepted, 2026-05-15)
- [ADR-0002](ADR-0002-active-storage-blob-retention.md) — 업로드 이미지 blob은 ParsingSession 종결 후 180일 보존하고 자동 purge한다 (Accepted, 2026-05-15)
- [ADR-0009](ADR-0009-vision-multi-institution-validation-via-dogfood.md) — Vision 파서의 멀티 기관 정확도는 사전 코퍼스 없이 dogfood로 점진 검증한다 (Accepted, 2026-05-15)
- [ADR-0010](ADR-0010-self-host-pretendard-variable.md) — Pretendard Variable을 dynamic-subset으로 자가 호스팅한다 (Accepted, 2026-05-15)
- [ADR-0011](ADR-0011-transaction-classification-source.md) — Transaction 단위 결정 메커니즘 보존 필드를 `classification_source` 컬럼으로 신설 (Accepted, 2026-05-16, ADR-0007 §2 후속)

### Design system 결정 묶음 (Accepted, 2026-05-15)

> `docs/discovery/2026-05-15-design-system-synthesis.md` + `2026-05-15-ui-redesign-plan.md`에서 승격된 결정들. 토스·뱅크샐러드 UI 해체분석 → 통합 → xef-scale 도메인 번역의 결과. ADR-0003이 우산 결정이며 나머지가 그 위에 얹힌다.

- [ADR-0003](ADR-0003-design-system-and-product-language.md) — Design system & Product Language 채택 (X1~X12 원칙 + 시맨틱 토큰 + 컴포넌트 사전 + Strangler Fig 마이그레이션)
- [ADR-0004](ADR-0004-review-inbox-as-top-level-tab.md) — 검토함을 IA 1번 시민으로 승격 (5탭 IA, "가져오기" 탭 폐기)
- [ADR-0005](ADR-0005-ad-free-policy.md) — 광고 청정 정책 명문화
- [ADR-0006](ADR-0006-separate-semantic-color-axes.md) — CTA와 시맨틱 컬러 축 분리 (action/positive/warning/info/danger)
- [ADR-0007](ADR-0007-category-source-visualization.md) — 카테고리 4단계 폴백 출처 시각화
- [ADR-0008](ADR-0008-light-first-with-dark-pair.md) — 라이트 우선, 다크 동등 지원

## 역사적 결정에 대한 메모

`docs/design-phase-a.md`, `docs/design-phase-b.md`는 큰 방향 결정의 *스냅샷*이지만 ADR 형식은 아니다. 본 PR은 이를 강제로 ADR로 백필하지 않는다. 향후 큰 결정이 phase-a/phase-b를 supersede 한다면, 새 ADR에 `Supersedes: docs/design-phase-b.md`로 명시한다.
