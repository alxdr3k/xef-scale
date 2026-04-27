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

(없음 — 본 PR은 ADR을 새로 만들지 않는다. 미래 결정이 추가되면 여기에 한 줄 인덱스)

## 역사적 결정에 대한 메모

`docs/design-phase-a.md`, `docs/design-phase-b.md`는 큰 방향 결정의 *스냅샷*이지만 ADR 형식은 아니다. 본 PR은 이를 강제로 ADR로 백필하지 않는다. 향후 큰 결정이 phase-a/phase-b를 supersede 한다면, 새 ADR에 `Supersedes: docs/design-phase-b.md`로 명시한다.
