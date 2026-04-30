# ADR-0001: Auto-post imports and repair only exceptions

## Status

Accepted

## Date

2026-04-30

## Context

현재 텍스트 붙여넣기와 이미지 업로드는 파싱 결과를 `pending_review` 거래로 만들고, 사용자가 검토 화면에서 commit해야 장부에 반영된다. 이 흐름은 안전하지만 사용자가 매번 "정리" 작업을 해야 하므로, 빠르게 지출 내역을 모으려는 핵심 사용 목적과 충돌한다.

실사용 피드백은 명확하다: 사용자는 정리가 귀찮아서 이 앱을 쓰려는 것이며, 모든 업로드 후 일일이 검토를 요구하면 사용성이 급격히 떨어진다. 따라서 정상적으로 파싱된 거래는 즉시 장부에 들어가야 한다.

다만 검토 단계를 제거하면 다음 안전장치가 사라진다.

- 중복 의심 거래를 commit 전에 막는 게이트.
- 잘못 파싱된 거래를 장부 반영 전에 수정하거나 제외하는 기회.
- 세션 단위 discard/rollback.
- commit 시점에 실행되던 예산 알림과 후속 상태 변경.

또한 이미지 상단이 잘린 화면처럼 날짜/가맹점/금액 중 필수 정보가 보이지 않는 거래는 `Transaction`으로 바로 만들 수 없다. 추정값으로 채우면 월별 지출, 중복 감지, 예산, 검색 결과가 오염된다.

## Decision

텍스트/이미지 파싱의 목표 UX를 "전체 검토 후 commit"에서 "정상 거래는 자동 등록, 예외만 수정 요청"으로 바꾼다.

구체적으로:

- 날짜/가맹점/금액이 모두 충분한 텍스트/이미지 파싱 결과는 파싱 잡 완료 시점에 `committed` 거래로 자동 저장한다.
- 필수 정보가 빠진 이미지 행, 애매한 중복 후보, 안전하게 자동 등록할 수 없는 행만 별도 repair queue에 보관한다.
- 필수 정보 누락 repair item은 세 곳에서 사용자에게 노출한다.
  1. 파싱 완료 직후 toast.
  2. 알림 dropdown/list.
  3. 결제 내역 페이지의 repair banner/filter.
- 이 세 지점의 action은 전체 검토 화면이 아니라 "수정이 필요한 행만" 보여주는 focused repair flow로 연결한다.
- repair flow에서 사용자가 누락 필수 셀을 채우면 그 행을 `committed` 거래로 승격하고 repair queue에서 제거한다.
- `ParsingSession`은 import batch 감사, 통계, undo/recovery의 컨테이너로 남긴다. `review_status`는 새 사용자 흐름의 게이트가 아니며, 기존 review route/view는 새 auto-post/repair/undo 흐름이 완성된 뒤 제거한다.
- 정확한 중복은 자동 제외할 수 있지만, 애매한 중복은 장부에 바로 넣지 않고 repair/duplicate issue로 남긴다.

## Consequences

긍정:

- 정상 케이스의 사용자 작업량이 크게 줄어든다.
- "업로드하면 장부가 갱신된다"는 단순한 mental model을 제공한다.
- 사용자는 전체 결과를 검토하지 않고, 실제로 문제가 있는 소수의 행만 처리한다.

부정 / 리스크:

- 잘못 파싱됐지만 필수값은 있는 거래가 장부에 바로 들어갈 수 있다.
- 검토 commit 시점에 모여 있던 예산 알림, 중복 처리, rollback/discard 책임을 파싱 잡과 별도 서비스로 옮겨야 한다.
- review controller/view/test를 한 번에 제거하면 회귀 범위가 크므로, auto-post, duplicate policy, repair queue, undo/recovery가 먼저 통과해야 한다.

필수 후속 작업:

- PRD, acceptance tests, traceability, current docs를 새 계약에 맞게 갱신한다.
- complete parsed rows를 `committed`로 저장하는 import finalization path를 만든다.
- 필수 정보 누락과 애매한 중복을 보관할 durable repair model을 만든다.
- toast/notification/transactions page repair entry point를 구현한다.
- repair item 승격 시 카테고리 매칭, 중복 정책, 예산 알림, source metadata를 동일하게 적용한다.
- 세션 단위 undo/recovery를 제공한 뒤 mandatory review route/view를 제거한다.

## Alternatives considered

### Keep mandatory review and make it faster

거래를 일괄 선택하거나 한 번에 commit하게 만들어도 "매번 검토해야 한다"는 부담은 남는다. 실사용 피드백의 핵심 문제를 해결하지 못한다.

### Auto-commit every parsed row, including incomplete or ambiguous rows

사용자 작업은 최소화되지만 장부 오염 위험이 크다. 특히 날짜가 없는 거래를 추정해서 넣으면 월별 예산과 중복 감지가 틀어진다.

### Store incomplete rows only in `ParsingSession#notes`

현재의 임시 방향이다. 조용히 버리지는 않지만 사용자가 수정해서 거래로 승격하는 경로가 없고, 실제 작업 표면과 안내 문구가 분리된다.

### Relax `Transaction` validations and store incomplete transactions directly

결제 내역 테이블에 한 번에 보여주기는 쉽지만, 날짜/금액이 없는 거래가 active ledger, 예산, 검색, API 응답에 섞일 위험이 있다. incomplete row는 ledger가 아니라 repair queue에 있어야 한다.

### Build a separate repair center only

예외 처리만 분리하면 모델은 명확하지만, 사용자가 결제 내역을 보러 온 맥락에서 수정 필요 상태를 놓칠 수 있다. 결제 내역 페이지 안에 repair banner/filter를 두고, 필요하면 전용 route를 그 필터의 구현 세부로 둔다.

## Supersedes

- The mandatory review/commit product flow described in `docs/01_PRD.md`, `docs/06_ACCEPTANCE_TESTS.md`, `docs/current/RUNTIME.md`, and historical Phase A/B docs, once the follow-up slices land.

## Superseded by

