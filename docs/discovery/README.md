# Discovery

진행 중인 탐색·Q&A·제품 리서치·임시 분석 노트의 홈.

## 규칙

- 디스커버리 노트는 **현재 구현의 권위가 아니다**. 미래의 에이전트는 코드와 얇은 현재 문서를 먼저 읽어야 한다.
- 디스커버리에서 수락된 결정이 나오면 `docs/decisions/`에 ADR을 만든다.
- 디스커버리가 제품 스코프를 바꾸면 `PRD.md`를 갱신한다.
- 디스커버리가 현재 동작 문서를 바꾸면 관련 얇은 문서를 같은 PR에서 갱신한다.

## 권장 파일명

- `YYYY-MM-DD-topic.md` — 한 토픽에 한 파일.
- 결과가 ADR이 되면 ADR 본문에 `Discovery: docs/discovery/...`로 링크.

## 현재 노트

- [2026-05-15-toss-ui-analysis.md](2026-05-15-toss-ui-analysis.md) — 토스 앱 UI 해체분석: 디자인 토큰·정책(P0~P15)·재구성 시뮬레이션·GPT 병행 분석·xef-scale용 디자인 시스템 제안.
- [2026-05-15-banksalad-ui-deconstruction.md](2026-05-15-banksalad-ui-deconstruction.md) — 뱅크샐러드 가계부 UI 해체분석: 원칙 10개 추출 → 외부 자료 교차검증 → GPT 병행 분석 부록 → xef-scale 디자인 시스템 명세.
- [2026-05-15-design-system-synthesis.md](2026-05-15-design-system-synthesis.md) — **토스 + 뱅샐 종합 보고서**: 두 분석을 통합한 xef-scale 디자인 시스템 결정 권고(원칙 X1~X12, 토큰, Product Language, 5탭 IA, UX Writing 사전, 의도적 마찰).
- [2026-05-15-ui-redesign-plan.md](2026-05-15-ui-redesign-plan.md) — xef-scale UI 재구성 실행 계획: 현재 진단 + 화면별 재구성 명세 + 단계별 로드맵 + 마이그레이션 전략.
