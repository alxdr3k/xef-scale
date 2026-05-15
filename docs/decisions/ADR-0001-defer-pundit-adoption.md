# ADR-0001: Pundit 채택을 보류하고 커스텀 권한 패턴을 유지한다

## Status

Accepted

## Date

2026-05-15

## Context

`app/controllers/application_controller.rb`는 `Pundit::Authorization`을 include하고 `Pundit::NotAuthorizedError`를 rescue하지만, 다음 사실이 확인된다.

- `app/policies/` 디렉토리가 존재하지 않는다.
- `authorize(...)`·`policy_scope(...)` 호출이 코드베이스 전체에서 0건이다.
- `Pundit::NotAuthorizedError`가 raise되는 경로가 없어 rescue 핸들러도 도달 불가다.
- Gemfile에 `gem "pundit"`이 명시되어 있고 잠금 파일에 2.5.2가 박혀 있다.

실제로 활성화된 권한 체크는 다음 두 곳에 분산되어 있다.

1. `ApplicationController#require_workspace_access` / `require_workspace_write_access` / `require_workspace_admin_access` — `User#can_read?` / `can_write?` / `admin_of?`(WorkspaceMembership role 기반)를 호출한다.
2. 리소스 단위 ad-hoc 메서드 — 예: `CommentsController#authorize_comment!`(작성자 또는 워크스페이스 admin).

이 패턴은 지금까지 잘 작동했고, 권한 경계가 (a) 워크스페이스 멤버십 역할, (b) "리소스 작성자"의 두 축으로 단순하다. 정책 객체를 도입할 만큼 매트릭스가 커지지 않았다.

## Decision

xef-scale은 **Pundit 정책 객체(`app/policies/*`)를 도입하지 않는다.** 현재의 커스텀 권한 패턴을 권위 있는 패턴으로 유지한다.

다만 `Pundit::Authorization` include와 `gem "pundit"` 의존성은 **그대로 둔다.** 두 가지 이유:

- 향후 트리거 발생 시 정책 도입 비용을 최소화한다 (gem 추가 PR 생략).
- Brakeman ignore가 "Pundit authorization in controller"를 근거로 한 규칙을 갖고 있어, 의존성 자체가 사라지면 별도 정리가 필요해진다.

## Consequences

긍정:
- 권한 로직이 컨트롤러와 `User` 모델에 명시적으로 남아 있어 추적이 쉽다.
- 정책 객체·테스트·런타임 dispatch 비용이 0이다.

부정:
- 컨트롤러에 ad-hoc `authorize_*!` 메서드가 늘어나면 중복이 발생할 위험이 있다 (`CommentsController#authorize_comment!`가 그 예).
- `Pundit::Authorization` include와 rescue가 "의도된 dead code"라는 점이 직관적이지 않다. 본 ADR이 그 문서적 근거다.

운영·테스트·문서 영향:
- `docs/context/current-state.md`의 "Needs audit" 항목에서 "Pundit 정책 도입 ADR 권장"을 제거하고 본 ADR로 링크한다.
- 새 권한 분기를 추가할 때는 우선 `User#can_*?` 또는 컨트롤러 헬퍼에 추가한다. 컨트롤러 외부(예: ActiveJob, MCP server) 에서 같은 권한이 필요해지면 `Authorization::*` 서비스를 만드는 것으로 시작한다 — Pundit 정책 객체로 점프하지 않는다.

## 재검토 트리거

다음 중 하나라도 충족되면 본 ADR을 supersede 하는 새 ADR로 Pundit 도입을 재평가한다.

1. ad-hoc `authorize_*!` 컨트롤러 헬퍼가 **3개 이상** 생긴다 (현재 1개: `CommentsController#authorize_comment!`).
2. 권한 경계 축이 **3개 이상**으로 늘어난다 (현재 2개: 워크스페이스 역할, 작성자).
3. 컨트롤러 외부(job/API/MCP)에서 동일 권한 로직이 **2회 이상** 중복된다.

## 모니터링

본 ADR의 효력을 유지할지 판단하려면 위 트리거를 주기적으로 측정해야 한다. 측정 방법과 이력은 아래와 같다.

측정 방법:

- 트리거 1: `grep -rn "def authorize_" app/controllers`
- 트리거 2: 권한 분기 식별자 카운트 — 워크스페이스 역할 (`User#admin_of?`/`can_write?`/`can_read?`)과 작성자(`@resource.user_id == current_user.id` 패턴).
- 트리거 3: `grep -rln "can_read?\|can_write?\|admin_of?" app/jobs app/services app/mailers app/controllers/api`

측정 이력:

| 일자 | 트리거 1 | 트리거 2 | 트리거 3 | 상태 |
|---|---|---|---|---|
| 2026-05-15 (ADR 채택) | 1 (`CommentsController#authorize_comment!`) | 2 (역할, 작성자) | 0 | 모두 미달 — 결정 유지 |
| 2026-05-15 (1차 재측정) | 1 | 2 | 0 | 변동 없음 — 결정 유지 |

## Alternatives considered

- **Pundit을 지금 도입해 `app/policies/`를 채운다** — 정책 객체 5~10개를 만들고 모든 컨트롤러에 `authorize` 호출을 도입한다. 거부 이유: 현재 권한 매트릭스가 단순해 추가 abstraction의 비용이 이득을 초과한다.
- **Pundit을 완전히 제거한다 (`gem "pundit"` 삭제, include 제거)** — dead code를 정리한다. 거부 이유: 향후 도입 비용을 의도적으로 낮춰두는 옵션 가치가 더 크다. Brakeman ignore 근거도 같이 정리해야 해 작업 범위가 커진다.

## Supersedes

없음 (첫 ADR).

## Superseded by

없음.
