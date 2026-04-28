# 07 Questions Register

아직 답이 정해지지 않은 열린 질문.

## How to use

1. 새 불확실성을 `Q-###`로 기록한다.
2. 제안된 답이 있으면 Proposed Answer에 남긴다.
3. 승인되면 [08_DECISION_REGISTER.md](08_DECISION_REGISTER.md) 또는 [decisions/](decisions/)의 ADR로 승격한다.
4. 질문을 resolved로 바꾸고 decision ID를 연결한다.

## Questions

### Q-001: 이미지 파싱을 신한카드 외 기관까지 제품 보장 범위로 확장할 것인가

- Opened: 2026-04-28
- Owner: product / engineering
- Status: open
- Proposed Answer: 현재 제품 계약은 "이미지 업로드 경로가 존재한다"까지로 두고, 비-신한 기관 정확도 보장은 별도 spike/ADR 후 확장한다.
- Blocks: REQ-003 expansion
- Resolution:

**Context**

현재 `GeminiVisionParserService` prompt는 신한카드 이용대금 명세서에 맞춰져 있다. 다른 기관 이미지는 입력 가능성이 있지만 정확도는 측정되지 않았다.

**Discussion**

- 후보 후속: 비-신한 샘플 fixture/eval 추가, 기관별 prompt/router 도입 여부 결정.

### Q-002: 텍스트 붙여넣기 경로에도 Gemini 카테고리 fallback을 도입할 것인가

- Opened: 2026-04-28
- Owner: product / engineering
- Status: open
- Proposed Answer: 현재는 텍스트 파싱에서 이미 AI를 호출하므로 카테고리화는 `CategoryMapping` + `Category#keyword`로 제한한다. 변경하려면 ADR이 필요하다.
- Blocks: REQ-007 expansion
- Resolution:

**Context**

이미지 경로는 미분류 거래에 Gemini 카테고리 fallback을 호출하지만, 텍스트 경로는 호출하지 않는다. 비용/지연/정확도 trade-off가 있다.

**Discussion**

- 후보 후속: 텍스트 경로 미분류율과 사용자 수정률 측정.

### Q-003: 초기 지표를 어디에서 어떻게 측정할 것인가

- Opened: 2026-04-28
- Owner: product / engineering
- Status: open
- Proposed Answer: PRD에는 지표 이름만 유지하고, 실제 instrumentation/dashboard는 별도 작업으로 정의한다.
- Blocks: Metrics section in `docs/01_PRD.md`
- Resolution:

**Context**

파싱 성공률, 중복 의심 비율, Gemini 카테고리 추천 적중률, commit 성공/실패는 제품적으로 유용하지만 현재 별도 analytics/dashboard 계약으로 정리되지 않았다.

**Discussion**

- 후보 후속: 이벤트/집계 저장소, 운영 대시보드, 개인정보 경계 정의.
