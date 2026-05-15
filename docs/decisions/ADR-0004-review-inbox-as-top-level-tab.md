# ADR-0004: 검토함을 IA 1번 시민으로 승격

## Status

Accepted

## Date

2026-05-15

## Context

xef-scale의 본질은 **3-way 입력(직접/SMS/이미지) → AI 파싱 → 검토 → 커밋**의 워크플로우다(`PRD.md`, `docs/context/current-state.md`). 즉 `pending_review` 상태는 단순한 임시 상태가 아니라 **사용자가 정기적으로 처리해야 하는 작업 큐**다.

현재 IA는 이를 반영하지 못한다:
- 모바일 하단 탭: 대시보드 / 결제 / 가져오기 / 설정 — 검토는 **"가져오기" 탭 안에 묻혀** 있다.
- "가져오기" → `parsing_sessions/index` → 입력 폼 + 세션 목록이 한 화면에 — 입력과 검토가 섞임.
- 검토 진입은 세션 카드를 클릭해야 함 — *검토 대기 N건* 같은 카운트가 IA 1번 레벨(탭 라벨/뱃지)에 노출 안 됨.
- 중복 의심 거래(`DuplicateConfirmation pending`)도 별도 진입로 없이 `reviews/show` 안에 묻힘.

토스·뱅크샐러드 모두 검토 머신을 *명시적*으로 두지 않는다(`pending_review`/`committed` 분리 자체가 xef-scale 차별점). 따라서 외부 벤치마크에 검토함 IA의 직접 참조는 없으나, 토스의 P0("한 화면 한 기능")과 뱅샐의 P9("직교 차원은 평탄 탭")이 검토함 분리를 지지한다(`synthesis.md 11장`).

## Decision

**모바일·데스크탑 공통 5탭 IA로 재구성**한다:

1. **홈** (`/dashboard` 또는 `/`) — 변동 카드, 검토 대기 카드(N>0일 때), 카테고리 breakdown, 반복 결제
2. **거래** (`/workspaces/:id/transactions`) — 목록·캘린더 듀얼 뷰
3. **검토함 ★** (`/workspaces/:id/reviews`) — *신규 IA 1번 시민*. `[파싱 결과 N | 중복 후보 M]` 세그먼트 탭
4. **카테고리** (`/workspaces/:id/categories`) — 카테고리 + 학습된 매핑
5. **더보기** (`/workspaces/:id/more`) — 워크스페이스, 멤버, AI 설정, 내 계정, 도구, 위험한 작업

세부 결정:
- 현재 "가져오기" 탭은 폐기. 입력 시트(3-way)는 검토함의 "+ 새로 가져오기" 액션으로 흡수.
- 검토함 탭에 미해결 카운트 뱃지(파싱 결과 + 중복) 노출.
- 모바일과 데스크탑이 동일 5탭. 데스크탑은 사이드바 또는 상단 nav, 모바일은 하단 탭바.
- 워크스페이스 스위처를 모바일에도 노출 (현재 데스크탑 전용).

**라우트 매핑 (현재 → 신규)**

현재(2026-05-15 기준 `config/routes.rb`):

- `parsing_sessions/:id/review` (member action) → `reviews#show`
- `reviews` 별도 resource 없음
- helper: `review_workspace_parsing_session_path(workspace, session)`

신규 (Phase 3에서 도입):

| Path | Action | Helper | 비고 |
|---|---|---|---|
| `GET /workspaces/:workspace_id/reviews` | `reviews#index` | `workspace_reviews_path(ws)` | **신설** — 검토함 인덱스. 파싱 결과 탭 + 중복 후보 탭 |
| `GET /workspaces/:workspace_id/parsing_sessions/:id/review` | `reviews#show` | `review_workspace_parsing_session_path(ws, ps)` | **유지** — 기존 path 보존 (북마크·외부 링크 호환) |
| 기타 `commit/rollback/discard/...` | (변경 없음) | (변경 없음) | 기존 nested member action 유지 |

신규 path 추가 외에는 기존 path를 **그대로 유지한다 — redirect 없음**. 신구 path 공존을 한 사이클(Phase 3~7) 운영한 뒤, 사용량 로그를 보고 옛 path의 단순화 여부를 별도 ADR로 결정한다.

라우트 코드 스케치:

```ruby
resources :workspaces, ... do
  resources :reviews, only: [ :index ]   # 신설
  resources :parsing_sessions, ... do    # 기존 그대로
    member { get :review, to: "reviews#show"; ... }
  end
end
```

`reviews#index`는 워크스페이스 스코프에서 `ParsingSession.where(review_status: "pending_review")` + `DuplicateConfirmation.pending` 양쪽을 합쳐 렌더하는 인덱스 액션이다. 세션 상세는 기존 helper(`review_workspace_parsing_session_path`)로 진입.

**ReviewsController 콜백 정정 (필수)**

현재 `ReviewsController`는 `before_action :set_parsing_session`를 모든 액션에 적용하며 `params[:parsing_session_id] || params[:id]`를 요구한다 (2026-05-15 기준). 신규 `index` 액션은 두 param 모두 없으므로 그대로 두면 `RecordNotFound`가 발생한다. Phase 3 구현 PR은 다음 중 하나를 반드시 포함해야 한다:

- `before_action :set_parsing_session, except: [ :index ]` (단일 컨트롤러 유지 + 콜백 스코핑)
- 또는 `reviews#index`를 별도 컨트롤러(예: `ReviewsInboxController`)에 분리

전자가 마이그레이션 비용이 낮아 권장.

## Consequences

**긍정**
- 사용자의 검토 워크플로우가 1탭 거리로 명시화됨.
- IA 1번 시민화로 미해결 검토량이 항상 보이는 *행동 압력* 발생.
- 입력과 검토가 분리되어 각 화면이 "한 화면 한 과업"(X2) 충족.
- 워크스페이스 공유 환경에서 "이 워크스페이스에 검토 대기 N건"이 자연스럽게 노출 — 다른 멤버에게도 가시화.
- 모바일/데스크탑 IA 통일로 어휘·진입 일관성.

**부정**
- 기존 사용자의 IA 학습 비용 (4탭 → 5탭).
- 기존 `parsing_sessions/index` 경로의 redirect 처리 필요.
- "가져오기" 어휘에 익숙한 사용자에게 "검토함"이라는 어휘 변화 부담.
- 더보기 탭 안에 메뉴가 누적될 위험 — 향후 hygiene 필요.

**완화**
- 기존 `/parsing_sessions` 경로는 한동안 유지하고 검토함으로 302 redirect + 토스트 안내.
- 첫 진입 시 새 IA 안내 모달 (Stimulus `onboarding_controller`).
- 더보기 탭에 검색 도입 (서비스 수 증가 시).

**테스트/문서 영향**
- `docs/code-map.md` 갱신: `reviews_controller#index` 신설.
- `docs/runtime.md` 갱신: 검토 진입 경로 변경.
- `docs/context/current-state.md` 갱신: 5탭 IA 명시.
- 컨트롤러·라우트 테스트 추가.

## Alternatives considered

1. **현 4탭 유지 + "가져오기"에 검토 강조** — 거부. 입력과 검토가 한 IA 노드에 있으면 두 과업이 섞여 "한 화면 한 과업"(X2) 위반.
2. **6탭** — 거부. 모바일 하단 탭에서 6탭은 가독성·터치 면적 한계.
3. **검토함을 홈 안의 카드로만 노출** — 거부. 카드는 한 단계 깊은 진입이고 카운트만 노출하기에 부족. 다만 홈의 `ReviewInboxCard`로 보조 진입은 *함께* 유지.
4. **"가져오기"를 "검토" 어휘로 단순 이름만 변경** — 거부. 입력 폼이 같은 화면에 있는 한 본질 문제 해결 안 됨.

## Supersedes

없음.

## References

- 디스커버리: `docs/discovery/2026-05-15-design-system-synthesis.md` (5장, 11장)
- 디스커버리: `docs/discovery/2026-05-15-ui-redesign-plan.md` (3.3, Phase 3)
- 관련 ADR: ADR-0003 (Design system 채택)
- 현재 상태: `docs/context/current-state.md`, `app/views/parsing_sessions/`, `app/views/reviews/`
