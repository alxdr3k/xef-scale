# 두 적대적 리뷰의 비판적 비교 + 통합 액션 플랜

- 일자: 2026-05-19
- 입력:
  - `docs/discovery/2026-05-19-ui-redesign-adversarial-review.md` (Claude 내부 리뷰)
  - `docs/discovery/2026-05-19-gpt-adversarial-review.md` (외부 GPT 리뷰)
- 본 문서의 권위 범위: **두 리뷰가 동의/충돌하는 지점을 추려 다음 PR의 우선순위로 잠금**.
- 디스커버리 노트. ADR이 권위.

---

## 0. 한 줄 요약

> **두 리뷰의 결론은 거의 같다("색·카피는 이겼고, IA·컴포넌트는 반쪽"). 그러나 *증거의 깊이*는 다르다.** GPT 리뷰가 더 잘 잡은 핵심 회귀(black/white token blind spot, `focus:outline-none` 충돌, calendar quick filter의 옛 경로 회귀, i18n baseline file-level 잔여)는 본인 리뷰가 놓친 것이고, 본인 리뷰가 더 깊게 잡은 것(X11 commit_locked UI 게이트, 워크스페이스 삭제 2단계 확인, 키보드 단축키 `x`/`cmd+enter` 미구현, 모바일 워크스페이스 스위처)은 GPT가 다루지 않은 영역이다. 따라서 *합치면 같은 점수에서 같은 결론*에 도달하지만 *합쳐야 다음 PR의 hardening 목록이 완성된다*.

---

## 1. GPT 리뷰가 더 정확히 잡은 것 — **본인 리뷰 미스 인정**

본인이 1차로 작성한 보고서는 다음 4건을 명백히 놓쳤거나 부정확하게 보고했다. GPT 주장은 직접 grep으로 검증 완료.

### 1.1 ❌ Semantic token contract의 black/white blind spot (본인 리뷰 큰 미스)

**본인 1차 보고**:
> "팔레트 utility 제거: ✅ 완료 — 0건 (landing/devise 제외)"
> "고정색 팔레트 (`bg-white`, `text-black`): 0개 (완전 제거)"

**실제 (검증됨)**:
- `app/views/shared/_flash.html.erb:6, 44` → `ring-1 ring-black/5`
- `app/views/shared/_input_sheet.html.erb:38` → `bg-black/40` (modal backdrop)
- `app/views/shared/_keyboard_shortcuts_help.html.erb:14` → `bg-black/40` (modal backdrop)
- `app/views/transactions/_duplicate_modal.html.erb:2` → `bg-black/50`
- `app/views/transactions/_edit_modal.html.erb:14` → `bg-black/50`
- `app/views/layouts/_navbar.html.erb:60, 104` → `ring-1 ring-black ring-opacity-5`
- `app/views/shared/_color_picker.html.erb:22` → `text-white` (체크 표시; non-landing)
- 그 외 landing/devise/일부 truncate_tooltip는 의도된 예외라 정당.

**왜 본인이 놓쳤나**:
- `test/contracts/semantic_token_contract_test.rb`의 forbidden palette 정규식이 `gray|slate|zinc|neutral|stone|indigo|blue|red|green|emerald|amber|yellow`만 잡고 **black/white를 제외**했다. 본인의 시각 시스템 서브에이전트는 *contract test 자체의 blind spot*을 못 봤다.
- `--color-overlay` 토큰이 `@theme`에 정의되어 있는데(`application.tailwind.css:39`), modal backdrop들이 그 토큰을 안 쓰고 raw `bg-black/40~50`을 직접 사용. 즉 *정의는 됐고 적용은 안 됐다*.

**합리적 반영**: GPT의 P1-5 그대로 채택. 즉시 fix.

### 1.2 ❌ Navbar `focus:outline-none`가 전역 focus-visible를 죽인다

**본인 1차 보고**:
> "focus ring 이중 정의 — 전역 `:focus-visible` + 인라인 `focus:ring-*` 공존. inline class가 우선이므로 전환이 부분적. (Phase 5 cleanup 후 정리되지 않은 잔재. 큰 문제는 아니지만 표준이 통일되지 않음)"

**실제 (검증됨)**:
- `_navbar.html.erb:39` (help button): `class="p-2 text-secondary hover:text-primary focus:outline-none cursor-pointer mr-2"` → **focus ring 없음, outline-none만**
- `_navbar.html.erb:49` (notification button): 동일 패턴 → **focus ring 없음**
- `_navbar.html.erb:80` (workspace select): `focus:outline-none focus:ring-action focus:border-action` → ring 있음, OK
- `_navbar.html.erb:93` (profile button): `focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-action` → ring 있음, OK

**왜 본인이 놓쳤나**:
- `focus:outline-none`이 Tailwind에서 `outline: 2px solid transparent` + specificity (0,1,0)로 컴파일된다. 전역 `:where(...):focus-visible` (specificity 0,0,0)을 *덮는다*.
- 따라서 help/notification 버튼은 **키보드 포커스가 시각적으로 보이지 않는다** — a11y 회귀.
- 본인 리뷰는 "큰 문제는 아니지만"으로 평가했는데, 실제로는 키보드 사용자에게 위치 손실 → WCAG 2.4.7(Focus Visible) 위반 가능.

**합리적 반영**: GPT의 P1-6 그대로 채택. P1 수준으로 상향. navbar:39, 49에 `focus-visible:ring-2 focus-visible:ring-action` 추가 + contract test 신설.

### 1.3 ❌ Calendar quick filters가 검토함이 아닌 parsing_sessions로 보냄

**본인 1차 보고**:
- 본인 리뷰 §2.1에서 "calendar 화면이 §3.1 명세를 따르지 않는다"고만 잡음.
- Quick filter 링크의 *목적지*가 옛 IA로 회귀하고 있다는 점은 못 봄.

**실제 (검증됨)**:
- `app/views/dashboards/calendar.html.erb:20` → `workspace_parsing_sessions_path(@workspace, ..., filter: 'needs_review')`
- `app/views/dashboards/calendar.html.erb:32` → `workspace_parsing_sessions_path(@workspace, ..., filter: 'has_duplicates')`

**왜 문제인가**:
- ADR-0004는 검토함이 IA 1번 시민이라고 명시했고, 사용자가 "지금 어디 검토할 게 있나" 묻는 *첫 화면 행동 압력*이 calendar의 needs_review/duplicate badge다.
- 그 badge가 *옛* IA (`parsing_sessions/index`)로 보내면, 새 IA(`reviews/index`)는 사용자가 navbar로 직접 진입한 경우에만 도달한다. 즉 *5탭 IA 승격*과 *첫 화면 행동 동선*이 분리되어 있다.

**합리적 반영**: GPT의 P2-7 그대로 채택. P1으로 상향 — IA 일관성 위반은 작은 결함이 아님.

### 1.4 ❌ i18n hardcoded Korean contract의 baseline이 file-level

**본인 1차 보고**:
> "i18n 키 사전 (synthesis 8장) — `config/locales/ko.yml`에 cta/live/empty/ai/risk/learn 그룹 100% 정의 ✅"
> "한글 카피 하드코딩 — view 안에 0건 ✅"

**실제 (검증됨)**:
- `test/contracts/i18n_hardcoded_korean_contract_test.rb:50-51`:
  ```ruby
  BASELINE_FILES_WITH_KOREAN = %w[
    app/views/pages/landing.html.erb
    app/views/shared/_context_header.html.erb
  ].freeze
  ```
- 같은 파일의 line 23: "파일 단위 baseline은 한 줄짜리 한글 추가도 막지 못한다는 한계가 있다."

**왜 본인이 놓쳤나**:
- "0건"이라는 결론은 *baseline 외부* 한정이었음. 본인 보고가 그 단서를 누락.
- baseline 파일(특히 `_context_header`)이 새 하드코딩 카피의 *쓰레기통*이 될 위험이 GPT 지적대로 실제로 있음.

**합리적 반영**: GPT의 P2-6 그대로 채택. baseline을 line-count 또는 exact-line으로 변경.

### 1.5 ❌ Navbar regex `\/reviews\?` 죽은 분기

**본인 IA 서브에이전트의 보고**:
> "활성 상태 감지 비일관성 — 검토함: `/parsing_sessions/` 경로도 활성 처리 (폴백). 더보기: 3개 경로 다중 폴백. 코드 복잡성 증가."

본인은 *복잡성*은 잡았지만 *dead branch*는 못 봄.

**실제 (검증됨)**:
- `_navbar.html.erb:18`: `request.path.match?(/\/reviews\z|\/reviews\?|\/parsing_sessions/)`
- `_mobile_bottom_nav.html.erb:23`: 동일
- `request.path`에는 query string이 없으므로 `\/reviews\?`는 절대 매치되지 않음 — **죽은 분기**.

**합리적 반영**: GPT의 P3-1 채택. 활성 헬퍼로 추출.

---

## 2. 본인 리뷰가 더 깊게 잡은 것 — GPT 리뷰가 다루지 않은 영역

GPT 리뷰는 시각·IA·컴포넌트 거버넌스에 강하지만, **X11(의도적 마찰)과 키보드 단축키, 모바일 워크스페이스 스위처는 거의 다루지 않았다**. 본인 리뷰가 보완해야 할 영역이다.

| 본인 리뷰 발견 | GPT 다룸? | 비고 |
|---|---|---|
| **X11 commit_locked UI 게이트 없음** (`reviews/show.html.erb:80-99` 무조건 활성, 서버 redirect만 가드) | ❌ | 본인 리뷰만 깊이. `risk.commit_locked` 카피는 ko.yml에 있는데 view에서 미사용. |
| **워크스페이스 삭제 single-confirm only** (이름 입력 단계 없음) | ❌ | 본인 리뷰만. ADR-0003 X11 + synthesis §9 명시 위반. |
| **bulk_delete 영향 범위(금액 합계) 미주입** | ❌ | 본인 리뷰만. `risk.bulk_delete` 카피는 건수만, 합계 placeholder 없음. |
| **rollback confirm에 거래 건수 미주입** (`risk.rollback_session` 카피 존재, 미사용) | ❌ | 본인 리뷰만. |
| **키보드 단축키 `x`(중복 표시), `cmd/ctrl+enter`(전체 반영) 미구현** | ❌ | 본인 리뷰만. `review_keyboard_controller.js:17` 주석 자백. |
| **enter 의미 변경** (synthesis: "다음 거래" → 실제: "선택 토글") — supersede ADR 없음 | ❌ | 본인 리뷰만. |
| **모바일 워크스페이스 스위처 미노출** (더보기 안 3단계 진입) | ❌ | 본인 리뷰만. ADR-0004 §"라우트 매핑" 부수 결정. |
| **누락된 8~9개 shared partial 전체 목록** | 일부 (3개) | 본인이 더 포괄적: `_chip_scroller`, `_filter_sheet`, `_bottom_sheet`, `_sticky_action_bar`, `_risk_notice`, `_workspace_switcher`, `_ai_badge_card`까지. |
| **`_amount` 직접 호출 30개 파일 카운트** | 정성적 언급 | 본인이 정량 카운트. |

---

## 3. 두 리뷰가 동의하는 핵심 — **확실한 미스**

다음은 두 리뷰가 *독립적으로* 같은 결론에 도달한 것 — 가장 신뢰할 수 있는 베이스라인.

1. **인증 root가 calendar라 Phase 4 hero/variance/review_inbox가 첫 화면 보장이 아니다** (본인 §2.1, GPT P1-2).
2. **`dashboards/_tabs.html.erb` 폐기 실패** + **`shared/_segmented_tabs` 부재** — 4개 dashboard view에서 잔존 호출 (본인 §2.2, GPT P1-4/P2-5).
3. **transactions/index가 §3.2 명세 거의 미반영** — inline form, 옛 table, ChipScroller/FilterSheet 부재 (본인 §2.4, GPT P1-3).
4. **reviews/index는 IA 승격 + 골조만, workbench 아님** (본인 §2.5, GPT P2-1).
5. **컴포넌트 사전 *지배력* 부족** — partial은 있지만 inline h1/p 잔존, ContextHeader/HeroStat/Amount 채택률 낮음 (본인 §3.3, GPT P1-4).
6. **Duplicate UI 3-way 분기 미통합** (본인 §4.6, GPT P1-7) — 다만 본인 검증으로 *호출은 살아있음* (각 partial이 transactions/index:216, reviews/show:70에서 호출됨). 즉 *좀비는 아니지만 단일화 미완료*.

---

## 4. 점수 재조정

본인 1차 보고의 점수 추정:

| 영역 | 본인 1차 | 조정 후 | 사유 |
|---|---|---|---|
| 인프라 (토큰/다크/i18n/폰트) | 92 | **80** | black/white blind spot + i18n baseline 잔여 → contract 자체가 깨졌으므로 깎음 |
| 5탭 IA + 검토함 승격 | 85 | **75** | 카테고리 admin-only로 비-admin은 4탭. ADR-0004 "공통 5탭" 거짓 |
| 시각 시스템 (팔레트→시맨틱) | 90 | **75** | bg-black/* 잔존 5+ 곳, focus:outline-none 단독 사용 (a11y 회귀) |
| 컴포넌트 사전 | 55 | **55** | 그대로 — 누락 partial + 채택률 낮음 |
| 화면 단위 To-Be (홈/거래/검토함) | 40 | **40** | 그대로 |
| X11 + 키보드 단축키 | 35 | **35** | 그대로 |
| **종합** | ~70 | **~65** | black/white 토큰 회귀와 focus a11y 회귀를 반영 |

---

## 5. 통합 액션 플랜 — 다음 PR 1개 추천

GPT의 PR 제목을 그대로 채택:

```
fix(ui-roadmap): lock IA/component contracts and finish transaction surface
```

### 5.1 🔴 P0 — 즉시 (a11y / 시각 회귀 / IA 정합성)

| # | 작업 | 근거 | 파일 |
|---|---|---|---|
| 1 | **navbar focus a11y fix** | GPT P1-6 (검증됨) | `_navbar.html.erb:39, 49` — `focus-visible:ring-2 focus-visible:ring-action` 추가 |
| 2 | **bg-black/* → bg-overlay** | GPT P1-5 (검증됨) | `_input_sheet.html.erb:38`, `_keyboard_shortcuts_help.html.erb:14`, `_duplicate_modal.html.erb:2`, `_edit_modal.html.erb:14` |
| 3 | **ring-black/5 → ring-divider** | GPT P1-5 | `_flash.html.erb:6, 44`, `_navbar.html.erb:60, 104` |
| 4 | **semantic_token_contract regex 확장** | GPT P1-5 | `test/contracts/semantic_token_contract_test.rb` — `\bbg-(black\|white)\b`, `\bring-(black\|white)\b`, `\btext-(black\|white)\b` 추가 |
| 5 | **commit_locked UI 게이트** | 본인 §2.6.1 (검증됨) | `reviews/show.html.erb:80-99` — `@parsing_session.has_unresolved_duplicates?` 시 disabled + `t("risk.commit_locked", count: ...)` 표시 |
| 6 | **calendar quick filter 목적지 교정** | GPT P2-7 (검증됨) | `dashboards/calendar.html.erb:20, 32` — `workspace_parsing_sessions_path` → `workspace_reviews_path`. reviews_controller에 `?filter=needs_review\|has_duplicates` 처리 추가 |
| 7 | **active nav helper 추출 + dead regex 제거** | GPT P3-1 | `app/helpers/navigation_helper.rb` 신설, `\/reviews\?` 분기 제거 |

### 5.2 🔴 P0 — 결정 필요 (ADR로 잠금)

| # | 결정 | 옵션 | 파일 |
|---|---|---|---|
| 8 | **홈 정의** | A. root=monthly로 이동 / B. calendar에 hero+variance+review_inbox stack / C. calendar-first로 ADR 개정 | 새 ADR. `docs/decisions/ADR-0012-home-screen.md` |
| 9 | **카테고리 nav role policy** | A. 모든 read 이상에게 read-only 노출 / B. 4/5탭 role-adaptive 공식화 + ADR-0004 개정 | ADR-0004 supersede 또는 amendment |
| 10 | **워크스페이스 삭제 2단계** | 이름 입력 단계 추가 (Stimulus 모달) | `workspace_more/show.html.erb` + 신규 컨트롤러 |

### 5.3 🟡 P1 — 단기 (컴포넌트 사전 강제)

| # | 작업 | 근거 | 비고 |
|---|---|---|---|
| 11 | **`shared/_segmented_tabs.html.erb` 신설** | 두 리뷰 | `_tabs` + `reviews/index` 인라인 흡수 |
| 12 | **`shared/_empty_state.html.erb` 신설** | 두 리뷰 | reviews/index, transactions/index, categories/index의 인라인 empty state 통합 |
| 13 | **`shared/_chip_scroller.html.erb` + `_filter_sheet.html.erb` 신설** | 두 리뷰 | transactions/index 거래 화면 재구성 |
| 14 | **`shared/_sticky_action_bar.html.erb` 신설** | 본인 §2.5 | reviews/show commit 영역 + duplicate sticky |
| 15 | **`shared/_risk_notice.html.erb` 신설 + 모든 위험 행동에 영향 범위 주입** | 본인 §2.6 | bulk_delete(amount), rollback(count), workspace_leave(workspace) |
| 16 | **`shared/_workspace_switcher.html.erb` 신설 + 모바일 노출** | 본인 §3.1 | `_navbar` line 76-89 추출, mobile_bottom_nav 또는 ContextHeader에 |
| 17 | **`shared/_bottom_sheet.html.erb` 신설** | 본인 §2.3 | `_input_sheet` 일반화 |
| 18 | **`shared/_ai_badge_card.html.erb` 신설** | 본인 §2.3 | 카테고리/검토함 AI 추천 |
| 19 | **`dashboards/_tabs.html.erb` 제거** | 두 리뷰 | #11 도입 후 4 view 일괄 교체 |
| 20 | **i18n baseline을 file-level → line-count or exact-line** | GPT P2-6 | `_context_header` 안 한글 예시는 i18n-allow line marker로 |

### 5.4 🟢 P2 — 중기 (컴포넌트 채택률 강제)

| # | 작업 | 근거 |
|---|---|---|
| 21 | `ContextHeader` 채택 contract test (대상 페이지 allowlist 점진 축소) | GPT P1-4 |
| 22 | `_amount` 채택 contract test — view 안 직접 `number_to_currency` 금지 (CSV/email 제외) | GPT P2-4, 본인 §3.5 |
| 23 | `focus:outline-none` contract test — 동일 element에 `focus-visible:ring` 없으면 fail | GPT P1-6 |
| 24 | duplicate UI 3-way 단일화 (`duplicate_confirmations/_row.html.erb`) | GPT P1-7, 본인 §4.6 |
| 25 | 키보드 단축키 `x` 구현 (중복 표시) | 본인 §3.4 |
| 26 | 키보드 단축키 `cmd/ctrl+enter` 구현 (전체 반영) | 본인 §3.4 |
| 27 | enter 의미 — ADR/카피 정렬 (synthesis "다음 거래" vs 실제 "선택 토글") | 본인 §3.4 |
| 28 | transactions/index의 중복 검사 버튼 → 검토함으로 이동 또는 wrapper로 축소 | 두 리뷰 |
| 29 | More page 정보구조 확장 (멤버/초대/예산/AI 설정/API 키 통합) OR 로드맵 §3.5 축소 | GPT P2-2 |
| 30 | reviews/index를 *queue/list*로 ADR 명시화 (inline workbench는 별도 milestone) | GPT P2-1 |

---

## 6. 본인 1차 리뷰 retro — 무엇을 놓쳤고 왜 놓쳤나

| 미스 | 원인 | 다음에 대비 |
|---|---|---|
| black/white 토큰 잔존 5+ 곳 | 시각 시스템 서브에이전트의 grep 패턴이 contract test의 forbidden regex를 그대로 따라했음. **contract test 자체의 blind spot을 못 봄** | 다음 감사는 *contract test를 먼저 메타 감사* — 정규식 자체를 비판적으로 분석 |
| `focus:outline-none` 단독 사용 | "focus ring 이중 정의"로 두루뭉술 처리. 실제로는 *outline-none이 ring을 죽이는 specificity 효과* 분석 안 함 | Tailwind utility의 컴파일 결과 + CSS specificity 비교를 audit 체크리스트에 추가 |
| calendar quick filter 목적지 | calendar.html.erb 본문은 읽었지만 `link_to ... workspace_parsing_sessions_path`를 IA 관점이 아니라 시각 관점으로만 봄 | 모든 외부 링크의 *목적지*를 IA 매트릭스로 매핑 |
| i18n baseline 잔여 | "한글 0건"만 보고 baseline 파일 안의 한글은 안 봄 | contract test의 *예외 목록*을 항상 확인 |
| dead regex `\/reviews\?` | regex 패턴은 봤지만 `request.path` 의미를 안 따짐 | regex를 본 시점에 *입력 도메인*과 매칭 검증 |

**교훈**: contract test가 있다고 해서 *contract test가 옳다*는 의미는 아니다. 다음 적대적 리뷰는 *test 자체*를 1차 타깃으로.

---

## 7. GPT 리뷰 retro — GPT가 약한 영역

GPT 리뷰는 정적 소스 + PR 메타데이터 기반이라 다음이 약했다.

1. **상태 머신 / 컨트롤러 가드 깊이** — `reviews_controller#commit`의 서버 측 중복 가드는 봤지만, *UI 게이트와의 균열*은 본인 리뷰가 더 깊음.
2. **카피 키와 view 사이의 *적용 깊이*** — `risk.bulk_delete`, `risk.rollback_session` 같은 카피가 *키만 있고 view에서 미사용*인 패턴은 GPT가 다루지 않음.
3. **모바일 IA / 워크스페이스 스위처** — 데스크탑 코드만 보면 잡기 어려운 mobile-specific 회귀.
4. **키보드 단축키 매핑 충돌** — `review_keyboard_controller.js` 안 주석 ("x=duplicate)는 후속 슬라이스")을 깊이 분석한 건 본인 리뷰만.

즉 *두 리뷰는 보완적*이다.

---

## 8. 한 줄 마지막

> 두 리뷰가 합쳐서 가리키는 곳은 단 하나: **다음 PR은 새 화면이 아니라 *계약을 잠그는 hardening***이다. P0 7개 + 결정 3개 + P1 10개 + P2 10개. 새 기능 추가 전에 이걸 닫지 않으면 Phase 8을 시작해도 *문서와 구현의 균열*이 더 벌어진다.

---

## 9. 상태표 (post-merge, 2026-05-21)

본 액션 플랜이 작성된 뒤 #247/#248/#249/#250 으로 일부 항목이 닫혔다. 다음 작업자가 stale finding 을 다시 집어 들거나, 반대로 open finding 을 closed 로 착각하지 않도록 명시한다. 본 표가 자동으로 갱신되지는 않으므로, 신규 PR 에서 본 액션 플랜의 항목을 닫으면 같은 PR 에서 본 표도 갱신할 것.

### 9.1 P0 — 즉시 (5.1)

| # | 작업 | 상태 | 닫은 PR / 비고 |
|---|---|---|---|
| 1 | navbar focus a11y fix | ✅ fixed | #247 (`_navbar.html.erb:39, 49` 에 `focus:ring-2 focus:ring-offset-2 focus:ring-action` 추가). 회귀 contract 는 아직 없음 — F6 후속. |
| 2 | bg-black/* → bg-overlay | ✅ fixed | #247 (modal backdrop 들이 `bg-overlay` 사용). |
| 3 | ring-black/5 → ring-divider | ✅ fixed | #247 (flash/navbar). |
| 4 | semantic_token_contract regex 확장 | ✅ fixed | #247 (`BLACK_WHITE_UTILITY_RE` 가 opacity suffix + arbitrary opacity 까지 매칭). 단 `PATH_ALLOWLIST` 는 여전히 path-level — 후속 hardening. |
| 5 | commit_locked UI 게이트 | ✅ fixed | #248 (blocked 상태에서 `commitForm` 자체 미렌더. `requestSubmit()` 우회 차단). |
| 6 | calendar quick filter 목적지 교정 | ✅ fixed | #248 (`workspace_reviews_path(tab:)` 로 retarget). 워크스페이스-전체 스코프 라벨 명시는 #249 에서 "전체" prefix 로 보강. |
| 7 | active nav helper 추출 + dead regex 제거 | 🟡 partial | #247 에서 dead `/reviews?` regex 일부 정리. helper 추출은 아직 open. |

### 9.2 P0 — 결정 필요 (5.2)

| # | 결정 | 상태 | 비고 |
|---|---|---|---|
| 8 | 홈 정의 (root=monthly / hero stack / calendar-first ADR) | ❌ decision-needed | ADR 미작성. |
| 9 | 카테고리 nav role policy | ❌ decision-needed | ADR-0004 supersede/amendment 미작성. |
| 10 | 워크스페이스 삭제 2단계 (이름 입력) | ❌ open | 모달/컨트롤러 미구현. |

### 9.3 P1 — 단기 (5.3)

| # | 작업 | 상태 | 비고 |
|---|---|---|---|
| 11 | `shared/_segmented_tabs.html.erb` 신설 | ❌ open | |
| 12 | `shared/_empty_state.html.erb` 신설 | ❌ open | |
| 13 | `shared/_chip_scroller.html.erb` + `_filter_sheet.html.erb` 신설 | ❌ open | |
| 14 | `shared/_sticky_action_bar.html.erb` 신설 | ❌ open | |
| 15 | `shared/_risk_notice.html.erb` 신설 + 영향 범위 주입 | ❌ open | `risk.bulk_delete` / `risk.rollback_session` 카피는 ko.yml 에 있지만 view 미주입. |
| 16 | `shared/_workspace_switcher.html.erb` 신설 + 모바일 노출 | ❌ open | |
| 17 | `shared/_bottom_sheet.html.erb` 신설 | ❌ open | |
| 18 | `shared/_ai_badge_card.html.erb` 신설 | ❌ open | |
| 19 | `dashboards/_tabs.html.erb` 제거 | ❌ open | #11 도입 의존. |
| 20 | i18n baseline 을 file-level → line-count or exact-line | ❌ open | 현재 `BASELINE_FILES_WITH_KOREAN` 는 여전히 file-level (`landing.html.erb`, `_context_header.html.erb` 2 개). |

### 9.4 P2 — 중기 (5.4)

| # | 작업 | 상태 | 비고 |
|---|---|---|---|
| 21 | `ContextHeader` 채택 contract test | ❌ open | |
| 22 | `_amount` 채택 contract test | ❌ open | |
| 23 | `focus:outline-none` contract test | ❌ open | #247 spot-fix 후 회귀 가드 아직 없음. F6 후속. |
| 24 | duplicate UI 3-way 단일화 | ❌ open | |
| 25 | 키보드 단축키 `x` (중복 표시) | ❌ open | |
| 26 | 키보드 단축키 `cmd/ctrl+enter` (전체 반영) | ❌ open | |
| 27 | enter 의미 — ADR/카피 정렬 | ❌ open | |
| 28 | transactions/index 의 중복 검사 버튼 → 검토함 이동/축소 | ❌ open | |
| 29 | More page 정보구조 확장 OR 로드맵 §3.5 축소 | ❌ open | |
| 30 | reviews/index 를 queue/list 로 ADR 명시화 | ❌ open | |

### 9.5 본 액션 플랜 범위 밖이지만 같이 닫힌 hardening

본 액션 플랜의 항목은 아니지만, 후속 GPT 적대적 리뷰가 PR #240–#248 chain 에 추가로 잡은 metrics 신뢰성 finding 들이 #249/#250 에서 닫혔다 — 본 문서에 기록만 남긴다.

| Finding | 출처 | 상태 | 닫은 PR |
|---|---|---|---|
| metrics HTML invalid date → widened/empty report | GPT review on #241 (F1) | ✅ fixed | #249 (422 + sections suppress + raw input 보존) |
| `rate_section[:state]` HTML/CSV 미surface | GPT review on #243 (F2) | ✅ fixed | #249 (state 별 i18n + CSV state row) |
| calendar action strip 워크스페이스-전체 스코프 라벨 | GPT review on #248 (F3) | ✅ fixed | #249 ("전체" prefix) |
| `text_for` unknown section type silent drop | GPT review on #243 (F9) | ✅ fixed | #249 (`ArgumentError raise`) |
| CSV_SCHEMA_VERSION not bumped on `state` row addition | codex review on #249 | ✅ fixed | #249 (v1 → v2) |
| `csv_for` unknown section type silent drop | GPT review on #249 (P2) | ✅ fixed | #250 (`ArgumentError raise`) |
| rate state 테스트 setup 주석 부정확 + exclusion `no_data` assertion 누락 | GPT review on #249 (P3) | ✅ fixed | #250 |
| #240 jwt 3.1.2 → 3.2.0 보안 업데이트 | GPT review on #240 chain (F4) | 🟡 in-progress | dependabot PR #240 rebase 후 머지 예정 |
| Stimulus required value completeness contract | GPT review (F5) | ❌ skipped | 회귀 미발생; cost/benefit 낮음 |
| `focus:outline-none` companion ring contract | GPT review (F6) | ❌ deferred | 위 #23 으로 통합 |
| i18n contract 의 user-visible model methods 부분 audit | GPT review (F7) | ❌ deferred | 전체 model surface 는 false positive 폭증; targeted audit 만 가능. 다음 i18n 작업 시 반영. |
| duplicate modal summary JS regression test | GPT review (F10) | ❌ skipped | rename trivial; system test 추가 과잉. |
| calendar copy "전체 기간 vs 전체 워크스페이스" 모호성 | GPT review on #249 | ❌ deferred | UX 영역; 사용자 피드백 후 결정. |
