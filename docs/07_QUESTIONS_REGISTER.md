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
- Blocks: `INP-1A.3`, `INP-1A.4`, `INP-1A.5`, REQ-003 expansion
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
- Blocks: `CAT-1A.2`, `CAT-1A.3`, REQ-007 expansion
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
- Blocks: `OBS-1A.4`, `OBS-1A.5`, Metrics section in `docs/01_PRD.md`
- Resolution:

**Context**

파싱 성공률, 중복 의심 비율, Gemini 카테고리 추천 적중률, commit 성공/실패는 제품적으로 유용하지만 현재 별도 analytics/dashboard 계약으로 정리되지 않았다.

**Discussion**

- 후보 후속: 이벤트/집계 저장소, 운영 대시보드, 개인정보 경계 정의.

### Q-004: 결제 provider와 과금 운영 방식을 무엇으로 할 것인가

- Opened: 2026-04-29
- Owner: product / engineering
- Status: open
- Proposed Answer: P1 사용 증거가 생기기 전에는 결제 구현을 시작하지 않는다. 후보는 Stripe, Toss Payments, PortOne/Iamport, 또는 invite-only/manual billing이다.
- Blocks: `BIZ-2A.2`, `BIZ-2A.3`
- Resolution:

**Context**

Phase B/C 설계는 자체 AI / BYOAI / 광고 제거 / 데이터 히스토리 제한을 수익 모델 후보로 잡았지만, 한국 결제 provider와 운영 방식은 아직 정하지 않았다.

**Discussion**

- 후보 후속: 한국 카드/정기결제 지원, 세금계산/영수증, 환불, subscription webhook, entitlement sync 비용 비교.

### Q-005: 네이티브 앱 / OS 통합을 언제 어떤 범위로 시작할 것인가

- Opened: 2026-04-29
- Owner: product / engineering
- Status: open
- Proposed Answer: 모바일 웹 + BYOAI path가 실제 사용에서 부족하다는 증거가 생길 때까지 deferred로 둔다. Android SMS 자동 파싱, iOS share extension, PWA camera upload은 각각 spike 후 결정한다.
- Blocks: `NTV-3A.1`, `NTV-3A.2`, `NTV-3A.3`, `NTV-3A.4`
- Resolution:

**Context**

iOS SMS 자동 읽기는 구조적으로 제한되고, Android SMS 자동 파싱은 Play 정책/권한/개인정보 비용이 크다. Phase B 설계는 네이티브 앱을 별도 트랙으로 미뤘다.

**Discussion**

- 후보 후속: 플랫폼 정책 확인, WWDC/Apple extension 변화 확인, Android SMS permission 정책 확인, Hotwire Native 유지보수 비용 산정.

### Q-006: 무료 / 유료 자체 AI / BYOAI tier 경계를 어디에 둘 것인가

- Opened: 2026-04-29
- Owner: product / engineering
- Status: open
- Proposed Answer: 무료는 기본 웹 입력과 제한된 데이터 히스토리, 유료는 Vision/무제한 히스토리/가족 공유/API-MCP 확장 후보로 두되 실제 사용 전 구현하지 않는다.
- Blocks: `BIZ-2A.1`, `BIZ-2A.4`, `BIZ-2A.5`
- Resolution:

**Context**

Phase B/C 설계는 무료 SMS 복붙, 유료 자체 AI, 유료 BYOAI, 광고 제거, 무제한 워크스페이스/히스토리를 후보로 제안했다. 현재 PRD에는 과금/광고/제한 정책이 제품 계약으로 들어와 있지 않다.

**Discussion**

- 후보 후속: 실제 사용량, Gemini 비용, 가족 공유 가치, API 사용 여부, retention 비용을 본 뒤 entitlement 모델 결정.

### Q-007: 업로드 원본 이미지와 파싱 산출물의 보존/삭제 정책은 무엇인가

- Opened: 2026-04-29
- Owner: product / engineering
- Status: open
- Proposed Answer: 파싱 완료/실패/discard/commit 각각에서 원본 ActiveStorage blob 보존 필요성을 결정하고, 개인정보 최소화 원칙과 디버깅 가능성 사이에서 명시적으로 선택한다.
- Blocks: `OPS-1A.1`
- Resolution:

**Context**

현재 이미지는 파싱 중 `Tempfile`로 다운로드 후 삭제되지만, ActiveStorage blob 자체의 명시적 보존/삭제 정책은 current docs에서 `needs audit`로 남아 있다.

**Discussion**

- 후보 후속: commit 후 삭제, 일정 기간 보존, 실패 건만 보존, 사용자가 직접 삭제 중 어떤 정책이 제품/운영에 맞는지 결정.

### Q-008: 운영 DB 백업/복구의 RPO/RTO/보관 정책은 무엇인가

- Opened: 2026-04-30
- Owner: product / engineering / ops
- Status: open
- Proposed Answer: 앱 코드 기준으로는 현재 `DatabaseBackupService`를 development/import 전용으로 격하하고, 하위호환 없이 새 environment-aware SQLite backup/restore primitive를 만든다. STG/PRD 운영 정책은 primary DB를 최소 복구 대상으로 두되, off-server 보관 위치, RPO/RTO, 보존 기간, 암호화/접근권한, queue/cache/cable DB 복구 범위는 별도 결정이 필요하다.
- Blocks: `OPS-1A.8`, `OPS-1A.9`
- Resolution:

**Context**

현재 production은 SQLite `primary`, `cache`, `queue`, `cable` DB 파일을 사용한다. 기존 `DatabaseBackupService`는 `storage/development.sqlite3`만 단순 복사하므로 운영 백업으로 신뢰할 수 없다. ActiveStorage blob 보존은 Q-007에서 별도로 다룬다.

**Discussion**

- 후보 후속: RPO/RTO, 백업 저장소(ops-managed volume snapshot, object storage, 별도 host 등), 보존 기간, 암호화/접근권한, restore drill 주기, queue/cache/cable DB를 복구 대상으로 볼지 또는 재생성 대상으로 볼지 결정.
