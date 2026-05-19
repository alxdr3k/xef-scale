# UI 재구성 로드맵 적대적 리뷰 (xef-scale)

- 일자: 2026-05-19
- 브랜치: `claude/review-ui-redesign-AgQmm`
- 기준 문서:
  - `docs/discovery/2026-05-15-design-system-synthesis.md` (X1~X12 헌법, 토큰, 컴포넌트 사전, 5탭 IA, 8장 카피)
  - `docs/discovery/2026-05-15-ui-redesign-plan.md` (As-Is 진단, 화면별 To-Be 명세, Phase 0~7 로드맵)
  - `docs/decisions/ADR-0003 ~ ADR-0008, ADR-0010` (승격된 결정)
- 방법: 4개 서브에이전트 병렬 감사(IA / 시각 시스템 / 컴포넌트 / 카피·a11y) + 직접 검증
- 톤: **적대적**. 잘 된 것은 짧게, 못 된 것을 길게.

---

## 0. 한 줄 결론

> **"토큰·다크모드·i18n·5탭 IA는 책 그대로 잘 깔렸고, 진짜 사용자 경험을 바꿔야 했던 §3.1 홈·§3.2 거래·§3.3 검토함의 화면 골조와 X11 의도적 마찰은 절반만 됐다."**

- ADR-기반 인프라 작업(토큰, 다크모드, i18n 키, 폰트 자가호스팅, 컬러 의미축 분리, 5탭 IA, 카테고리 출처 시각화): **잘 됨 (90%)**
- 화면 단위 To-Be 명세 (홈/거래/검토함 페이지의 컴포넌트 골조): **부분 (50~60%)**
- X11 의도적 마찰 / 키보드 단축키 / 모바일 워크스페이스 스위처: **약함 (30~40%)**

총평 점수: **이행도 약 70/100**. "Phase 5(다크모드/a11y), Phase 6(i18n), Phase 7(메트릭)에 집중 출근했고, Phase 3(IA) 화면 단위와 Phase 4 홈 레이아웃은 골조만 깔고 부품 미완료" 상태.

---

## 1. 잘 구현된 영역 (요약, 칭찬은 짧게)

| 영역 | 근거 | 상태 |
|---|---|---|
| 5탭 IA (홈/거래/검토함/카테고리/더보기) | `app/views/layouts/_navbar.html.erb`, `_mobile_bottom_nav.html.erb` 모두 5탭 동일 구성 | ✅ |
| 검토함 라우트 신설 | `config/routes.rb:69` `resources :reviews, only: [:index]`, `app/views/reviews/index.html.erb` 신설 | ✅ |
| 시맨틱 토큰 (@theme) | `app/assets/stylesheets/application.tailwind.css:33-136` — 모든 토큰 `light-dark()` 형식 | ✅ |
| 팔레트 utility 제거 | `bg-indigo-*`, `bg-gray-*`, `text-gray-*` 등 view에서 0건 (landing/devise 제외) | ✅ |
| AI 채널 격리 | `--color-ai` 보라 토큰 + `_category_source_chip.html.erb:31,56`, `_inline_alert.html.erb:34` 등 일관 사용 | ✅ |
| 다크 모드 | `User#theme` (`settings` JSON), `theme_controller.js`, `_screen_shell` + `data-theme` + `light-dark()` 페어링 | ✅ |
| Pretendard 자가호스팅 | `public/fonts/pretendard-1.3.9/` 92 subset + OFL 라이센스 (`public/licenses/pretendard-OFL-1.1.txt`) | ✅ |
| i18n 키 사전 (synthesis 8장) | `config/locales/ko.yml`에 cta/live/empty/ai/risk/learn 그룹 100% 정의 | ✅ |
| 한글 카피 하드코딩 | view 안에 0건 — `t()` 일괄 사용 | ✅ |
| TransactionRow 단일화 | `reviews/_transaction_row.html.erb` 폐기 완료, `transactions/_transaction_row.html.erb` 단일 (`reviewable`, `read_only` flag) | ✅ |
| 컬러 의미축 분리 (X5/ADR-0006) | action/positive/warning/info/danger/ai 6축 독립 토큰 | ✅ |
| Phase 7 메트릭 | `app/services/import_review_metrics_report.rb`, `app/views/metrics/`, CSV export (PR #239) | ✅ |
| 카테고리 출처 시각화 (ADR-0007) | `_category_source_chip` + 명시적 학습 opt-in (PR #167) | ✅ |
| HeroStat / VarianceCard / ReviewInboxCard / RecurringPaymentCard | `app/views/shared/_hero_stat.html.erb`, `_variance_card.html.erb`, `_review_inbox_card.html.erb`, `_recurring_payment_card.html.erb` 모두 신설 | ✅ (다만 호출 위치가 문제 — §3 참조) |
| focus ring 통일 | `application.tailwind.css:168-172` `:focus-visible` 글로벌 룰 + `--color-focus` 토큰 | ✅ |

칭찬 끝. 이제 본격 적대적 검토.

---

## 2. 🔴 심각 — 로드맵의 핵심 To-Be 명세를 비껴간 곳

### 2.1 "홈"이 로드맵 §3.1 명세를 따르지 않음 (가장 큰 미스)

**로드맵 §3.1 (`ui-redesign-plan.md:97-126`)**:
- `홈 (/dashboard → /)`은 `ContextHeader` → `MonthNav` → `HeroStat` → `VarianceCard` → `ReviewInboxCard` → "카테고리별 지출" Section → "반복 결제" Section 순서.
- "대표 행동: 이번 달 페이스 파악 + 검토 대기 처리 + 카테고리 드릴다운"

**실제 구현**:
- `config/routes.rb:21` — `authenticated :user do root "dashboards#calendar"`
- `config/routes.rb:118` — `get "dashboard", to: "dashboards#calendar"`
- ⇒ **사용자가 로그인 후 받는 화면 = `dashboards/calendar.html.erb`**

`dashboards/calendar.html.erb`을 읽어보면:
- `<h1>` + `<p>` 인라인 (line 3-5) — `_context_header` 사용 안 함
- `render 'tabs'` (line 7) — 폐기 대상 partial 호출 ❌
- action strip (line 10-55) — 필터 칩 (필요/중복/미분류)
- 월 네비 (line 62-68) — `_month_picker`도 `_month_nav`도 사용 안 함
- Calendar grid + Day detail Turbo Frame (line 70-153)

**`_hero_stat`, `_variance_card`, `_review_inbox_card`, `_recurring_payment_card`는 calendar.html.erb 어디에도 없음.**

이 카드들은 모두 `dashboards/monthly.html.erb:38, 48, 58, 66`에 있는데, monthly는 sub-tab 안쪽(/dashboard/monthly)에 있어 **사용자가 "홈" 탭을 눌렀을 때는 안 보임**. "이번 달 페이스 파악"이 명시적으로 §3.1의 "대표 행동"인데, 실제 홈에서는 보이지 않는다.

**적대적 판정**:
> 로드맵의 **§3.1 명세는 monthly.html.erb 위에 그려졌고, 실제 홈은 calendar.html.erb다**. 이 두 화면 사이에서 사용자가 어디서 무엇을 보는지 IA 결정이 불일치한 채 출시됐다. "홈을 calendar로 옮긴 것"이 별도 ADR로 승격되었거나 ui-redesign-plan을 supersede한 흔적이 없다.

**근거**:
- `config/routes.rb:21` (root authenticated → calendar)
- `app/views/dashboards/calendar.html.erb` (1-155)
- `app/views/dashboards/monthly.html.erb:26-71` (hero/variance/review_inbox/recurring 모음)
- `docs/discovery/2026-05-15-ui-redesign-plan.md:97-126` (§3.1 spec)

**즉시 해야 할 일 (둘 중 하나)**:
1. `dashboards#calendar` 액션에 hero/variance/review_inbox/recurring 카드 추가 — 로드맵에 맞춤.
2. 또는 `dashboards#monthly`를 root로 옮기고 calendar를 sub-route로 — 결정을 ADR로 남김.

---

### 2.2 폐기됐어야 할 `dashboards/_tabs.html.erb`가 4곳에서 살아있음

**로드맵 §4.4 폐기 대상**:
| 현재 | 처리 |
|---|---|
| `dashboards/_tabs.html.erb` | SegmentedTabs로 일반화로 흡수 |

**실제**:
```
$ grep -rn "render 'tabs'" app/views/dashboards/
dashboards/calendar.html.erb:7:  <%= render 'tabs' %>
dashboards/monthly.html.erb:9:   <%= render 'tabs' %>
dashboards/yearly.html.erb:7:    <%= render 'tabs' %>
dashboards/recurring.html.erb:7: <%= render 'tabs' %>
```

`dashboards/_tabs.html.erb`는 4개 sub-tab(`calendar | monthly | yearly | recurring`)을 가로로 펼친다. 이는 **5탭 IA의 1번 시민(홈) 안에 다시 4-탭 nested IA**가 있는 구조 — 로드맵 X2 ("한 화면 한 과업")과 정면 충돌.

또한 `shared/_segmented_tabs.html.erb`가 **존재하지 않는다**:
```
$ ls app/views/shared/_segmented_tabs.html.erb
ls: cannot access ...: No such file or directory
```

⇒ "_tabs를 SegmentedTabs로 흡수"하려고 했는데 SegmentedTabs partial 자체가 없다.

`reviews/index.html.erb:28-50`은 SegmentedTabs를 인라인 마크업으로 직접 구현 (`role="tablist"` + Stimulus `review-tabs`). 즉 컴포넌트 표준 없이 화면마다 다시 깎고 있음.

**근거**:
- `app/views/dashboards/_tabs.html.erb` (전체)
- `app/views/dashboards/{calendar,monthly,yearly,recurring}.html.erb:7~9`
- `app/views/reviews/index.html.erb:28-50` (인라인 segmented tabs)
- `docs/discovery/2026-05-15-ui-redesign-plan.md:308` (§4.4 폐기 명세)

---

### 2.3 신설했어야 할 핵심 shared partial 8~9개가 **존재 자체 안 함**

**로드맵 §4.1 신설 목록** 중 실제로 파일 없음:

| 신설 명세 | 의도된 용도 | 실제 |
|---|---|---|
| `shared/_segmented_tabs.html.erb` | 모드 전환 (목록/캘린더, 파싱/중복) — 컴포넌트 사전 6.3 | ❌ 없음. reviews/index와 dashboards/_tabs가 각각 인라인 마크업 |
| `shared/_chip_scroller.html.erb` | 필터 chip 가로 스크롤 (§3.2 거래) | ❌ 없음. transactions/index는 인라인 form `select` 그대로 |
| `shared/_filter_sheet.html.erb` | 필터 chip 클릭 → 시트 (§3.2) | ❌ 없음. 인라인 form 유지 |
| `shared/_bottom_sheet.html.erb` | 모바일 시트 일반화 | ❌ 없음. `_input_sheet`만 특수화로 존재 |
| `shared/_sticky_action_bar.html.erb` | 검토함 하단 듀얼 CTA (§3.3) | ❌ 없음. reviews/show는 인라인 `<div class="bg-surface...">` (reviews/show:78-101) |
| `shared/_empty_state.html.erb` | 빈 상태 통일 (X7) | ❌ 없음. reviews/index:94-98, transactions/index 등 각자 인라인 |
| `shared/_risk_notice.html.erb` | 비가역 액션 직전 경고 (X11) | ❌ 없음. 카피 키(`risk.*`)는 ko.yml에 있으나 호출 partial 없음 |
| `shared/_ai_badge_card.html.erb` | Gemini 추천 카드 (§3.4 카테고리) | ❌ 없음 |
| `shared/_workspace_switcher.html.erb` | navbar 워크스페이스 select 추출 (§4.1) | ❌ 없음. _navbar.html.erb:76-89 인라인 그대로 |
| `shared/_month_nav.html.erb` | `< 5월 >` 컨트롤 | ❌ 없음. `_month_picker`(드롭다운)와 페이지별 인라인 `link_to prev/next` 혼용 |

**즉**: 로드맵 §4.1의 "신설 partial" 20개 중 **약 절반은 만들어졌고, 가장 구조적인 절반(IA 골조에 해당)이 안 만들어졌다**.

만들어진 것은:
- `_screen_shell`, `_context_header`, `_hero_stat`, `_amount`, `_variance_card`, `_review_inbox_card`, `_inline_alert`, `_source_icon`, `_pending_badge`, `_category_source_chip`, `_recurring_payment_card`(보너스)

만들어지지 않은 것은:
- 모두 **레이아웃·구조** partial (`_segmented_tabs`, `_chip_scroller`, `_filter_sheet`, `_bottom_sheet`, `_sticky_action_bar`, `_empty_state`, `_risk_notice`, `_ai_badge_card`, `_workspace_switcher`, `_month_nav`)

**적대적 판정**: 
> "토큰을 먹는 카드"(badge·card 류)는 새로 만들었지만, "사용자가 IA를 탐색하는 도구"(시트·탭·sticky bar·empty state)는 인라인으로 남아 있다. 컴포넌트 사전(§6)이 코드화되지 않았다 — X12 "컴포넌트 거버넌스" 본문의 *의도*는 못 살림.

**근거**:
- `app/views/shared/` 디렉토리 리스팅 (위 표의 ❌들 모두 부재 확인)
- `docs/discovery/2026-05-15-ui-redesign-plan.md:264-287` (§4.1 신설 목록)

---

### 2.4 `transactions/index`는 로드맵 §3.2 명세 거의 미반영

**로드맵 §3.2 To-Be (`ui-redesign-plan.md:136-160`)**:
```
ContextHeader  "거래" + 라이브 "{보고 있는 기간 합계}"
SegmentedTabs  [목록 | 캘린더]
ChipScroller   (카테고리 · 금융기관 · 소스 · 상태 · 결제수단)
   ↑ 클릭하면 FilterSheet 진입
Toolbar  [🔍 검색] [+ 기록하기]   ← Floating fab (모바일)
(목록 뷰) DateGroupHeader sticky + TransactionRow
(캘린더 뷰) CalendarGrid
```

**실제 (`app/views/transactions/index.html.erb`)**:
- `<h1>` + `<p>` (line 26-29) — `_context_header` 미사용 ❌
- **SegmentedTabs [목록 | 캘린더] 없음** — 캘린더 뷰는 별도 라우트 `/dashboard/calendar`로 분리되어 있고 transactions 안에는 없음 ❌
- **ChipScroller 없음**. 필터는 인라인 `<form>` + `<select>` × 3 (line 35-65) — 로드맵 As-Is 진단(§1.5)이 지적한 바로 그 패턴이 그대로 ❌
- **FilterSheet 없음** ❌
- "+ 기록하기" CTA는 있지만(line 29) `link_to`로 새 페이지로 이동 — 시트가 아님 ❌
- 중복 검사 버튼(line 68-74) — 로드맵 §3.2는 "중복 검사 버튼 → 검토함 탭으로 이동"이라고 했는데 여기 그대로 살아있음. 게다가 `bg-warning text-action-on` 조합이 색 의미를 흐림 ❌
- DateGroupHeader sticky 없음 — 거래는 한 테이블에 쭉 나열

**즉**: §3.2 명세 6개 항목 중 **0~1개**만 실제로 반영됨. 이것은 Phase 2가 거래 컴포넌트 *통합*만 끝낸 결과 — Phase 3에서 IA 재구성을 하기로 했는데, transactions/index의 화면 골조는 손대지 않음.

**근거**:
- `app/views/transactions/index.html.erb:26-90`
- `docs/discovery/2026-05-15-ui-redesign-plan.md:136-160` (§3.2)

---

### 2.5 `reviews/index`는 골조만, 본문 컴포넌트 미완료

**로드맵 §3.3 To-Be (`ui-redesign-plan.md:164-192`)**:
```
ContextHeader
SegmentedTabs [파싱 결과 N | 중복 후보 M]
+ 새로 가져오기 (시트)

(파싱 결과 탭)
ParsingSessionCard × N (헤더: SourceIcon, 파일명, 시간 / 메타: N건·중복·badge / 미리보기: 원본 / TransactionRow × N 인라인 편집 / [반영 N건] [폐기])

(중복 후보 탭)
DuplicateConfirmationRow × N (좌우 비교 + 3-way 선택)

RiskNotice (미해결 중복 + commit 시도)
StickyActionBar [취소 | 거래 내역 반영 (N건)]
```

**실제 (`app/views/reviews/index.html.erb`)** — 본인이 주석으로 자백하고 있음:
- line 4: `본 PR은 *IA 골조*만 다룬다 (preflight §3.3, "PR B")`
- line 6: `구체 행 디자인은 후속 화면 PR`

즉 reviews/index는 **세션 목록을 link_to로 row로 표시**만 한다. 인라인 ParsingSessionCard도, DuplicateConfirmationRow도, RiskNotice도, StickyActionBar도 없다. 모든 진짜 검토 워크플로우는 `reviews/show.html.erb`(개별 세션)에 있고, index는 그쪽으로 보내는 디스패처에 가까움.

**자가 인식은 있다**(line 4-10에 후속 PR 약속). 다만:
- "후속 PR"이 commit 로그에 보이지 않음 — Phase 3 슬라이스 별도 없음.
- ADR-0004는 "검토함이 IA 1번 시민"이라고 했는데, 실제로는 1번 시민의 *내용*은 비었다.

**근거**:
- `app/views/reviews/index.html.erb:1-136`
- `docs/discovery/2026-05-15-ui-redesign-plan.md:164-192` (§3.3)
- git log: Phase 3 슬라이스 commit 없음 — Phase 5 a11y / Phase 6 i18n / Phase 7 metric만 있음

---

### 2.6 X11 의도적 마찰 — UI 게이트 부족

**로드맵 §9 (`design-system-synthesis.md:529-543`)**:
| 행동 | 마찰 장치 |
|---|---|
| `Transaction#commit` | 미해결 중복 자동 카운트 → **CTA 비활성 + 사유 명시** |
| 거래 일괄 삭제 | RiskNotice + **삭제 건수·합계 표시** |
| `CategoryMapping` 일괄 재적용 | "거래 N건이 새 카테고리로 바뀌어요" 미리보기 |
| 워크스페이스 탈퇴/삭제 | **2단계 확인 + 워크스페이스명 직접 입력** |
| `ParsingSession` rollback | "이 세션의 거래 N건이 검토 전 상태로 돌아가요" |

ko.yml에 카피 키는 모두 있다 (`risk.commit_locked`, `risk.bulk_delete`, `risk.workspace_delete`, `risk.rollback_session` — `config/locales/ko.yml` 8장 사전 영역).

**실제 구현**:

#### 2.6.1 commit_locked: 서버 가드 O, UI 가드 X
- 서버: `app/controllers/reviews_controller.rb:commit` 안에 `if @parsing_session.has_unresolved_duplicates? redirect ... alert: ...` ✅
- UI: `app/views/reviews/show.html.erb:80-99` — commit 버튼이 **무조건 활성**. `<button type="submit" class="...bg-positive...">` — disabled 조건 없음.
- 결과: 사용자는 미해결 중복이 있어도 commit을 누른다 → redirect + flash alert. 로드맵 명세는 *비활성 + 사유 명시*인데, 실제는 *클릭 후 거부*.

`_duplicate_section.html.erb`이 warning banner를 보여주긴 하지만 commit 버튼과 *시각적·논리적으로 묶여 있지 않다*. 한 사용자가 duplicate section을 스크롤 지나치고 commit 버튼만 보면 클릭하게 됨. 이것이 X11 위반.

#### 2.6.2 워크스페이스 삭제: 1단계만
- `app/views/workspace_more/show.html.erb:114-121` — `data: { turbo_confirm: t("workspace_more.delete_confirm") }` 하나만.
- ko.yml `workspace_more.delete_confirm` — "워크스페이스를 삭제하면 모든 거래·카테고리·매핑·세션이 함께 삭제됩니다. 계속하시겠습니까?"
- 로드맵 명세 **"2단계 확인 + 워크스페이스명 직접 입력"** — 후자(이름 입력) 미구현. 토스의 모든 destructive에서 "이름을 입력하세요"를 요구하는 것과 대조.

#### 2.6.3 bulk_delete: 금액 합계 미표시
- `ko.yml:js_bulk.delete_payment_confirm_template` = `"선택한 __COUNT__개의 결제를 삭제하시겠습니까?"` — 건수만, 합계 없음.
- 로드맵 §9 명시: "RiskNotice + 삭제 건수·합계 표시". 합계가 빠지면 사용자가 영향을 가늠하기 어려움.

#### 2.6.4 rollback: 거래 건수 미주입
- `app/views/reviews/show.html.erb:137-142` — `turbo_confirm: t("reviews.show.rollback_confirm")`
- 카피: "이번 가져오기를 모두 되돌리시겠습니까? 이 작업은 되돌릴 수 없습니다."
- ko.yml의 `risk.rollback_session`은 **"이 세션의 거래 %{count}건이 모두 검토 전 상태로 돌아가요"** — N건 명시. 이 키는 *존재하지만 사용되지 않음*. 실제 confirm은 generic.

**적대적 판정**:
> "키는 다 추가했지만 view에 t() 호출이 안 된" 전형적 사례. ko.yml에 사전을 채우는 PR(#225~#234)이 9개나 있는데, "위험 행동 카피"의 *적용 깊이*는 piecemeal. X11이 카피 사전 채우기로 끝났고 UI 시그널과 게이트는 못 따라옴.

**근거**:
- `app/controllers/reviews_controller.rb:commit` (서버 가드만)
- `app/views/reviews/show.html.erb:80-99` (commit 버튼 무조건 활성)
- `app/views/workspace_more/show.html.erb:114-121` (single confirm)
- `config/locales/ko.yml:risk.rollback_session, risk.bulk_delete, risk.workspace_delete` (정의됐으나 단순 confirm으로만 일부 사용)
- `docs/discovery/2026-05-15-design-system-synthesis.md:529-543` (§9 명세)

---

## 3. 🟡 중간 — 부분 이행 / 일관성 갱신 필요

### 3.1 모바일 워크스페이스 스위처 미노출

**로드맵 §3.1, §3.5 (`ui-redesign-plan.md:104, 255`)**: "모바일에서 워크스페이스 스위처: ContextHeader 우측에 노출 (모든 화면)"

**실제**:
- `app/views/layouts/_navbar.html.erb:76-89`에 데스크탑 select 있음 (`hidden sm:flex` 안 — 모바일에서는 안 보임).
- `app/views/layouts/_mobile_bottom_nav.html.erb` — 스위처 없음.
- 모바일에서 워크스페이스 전환하려면: **더보기(5번 탭) → "다른 워크스페이스로 이동" 링크** (`workspace_more/show.html.erb:38-41`) — 3단계.

**적대적 판정**: 5탭 IA는 데스크탑/모바일 동등인데, 워크스페이스 스위처라는 *상시 컨텍스트*는 모바일에서 5번 탭 안에 묻혔다. 이는 ADR-0004가 명시한 *공유 환경의 워크스페이스 인지*에 반함.

### 3.2 `parsing_sessions/index`는 명시적 호환 보존이지만 이중 진입로

`app/views/parsing_sessions/index.html.erb:7-10`에 자가 주석:
> "입력 폼은 검토함의 '+ 새로 가져오기' 시트로 이동했다. 본 페이지는 *입력 기록*만 노출한다. parsing_sessions/index 라우트는 북마크·외부 링크 호환을 위해 유지하지만, 여기에서도 같은 시트로 새로 가져오기를 시작할 수 있도록 trigger를 둔다."

이는 **의도된 호환성 carve-out** — 비판하기는 어렵다. 다만:
- 더 이상 5탭 어디에도 링크가 없는 페이지(가져오기 탭이 없으니까)인데 라우트만 유지됨.
- "같은 시트를 여기서도" 둠으로써 입력 진입로가 두 곳(reviews/index + parsing_sessions/index) — IA 단순화 목표와 충돌.

**중간 처리 권고**: `redirect_to workspace_reviews_path`로 영구 이전하거나, "입력 기록"이라는 이름의 화면을 더보기 안에 노출. 현재는 dangling 페이지.

### 3.3 ContextHeader 적용 불완전

`_context_header.html.erb`는 partial로 존재(37 lines). 그러나 실제 호출:
- `layouts/application.html.erb` 또는 `_screen_shell`에서 자동 호출 안 됨.
- 페이지들이 여전히 `<h1>` + `<p>` 인라인 사용:
  - `dashboards/monthly.html.erb:5-6`
  - `dashboards/calendar.html.erb:3-4`
  - `reviews/index.html.erb:15-18`
  - `transactions/index.html.erb:26-29`
  - `workspace_more/show.html.erb` 등

⇒ `_context_header.html.erb`는 *문서로서* 존재하지만, **실제 채택률은 0~5%**. Strangler Fig 패턴이라고 봐줄 수도 있지만, Phase 1~4 종료 이후 진행 흔적이 없음.

### 3.4 키보드 단축키 — `x`, `cmd/ctrl+enter` 미구현

**로드맵 §3.3, §7.3 (synthesis)**:
- j/k/c/d/x/enter/cmd+enter 7개

**실제 (`app/javascript/controllers/review_keyboard_controller.js`)**:
- j/k (focusRelative): ✅
- c (commit form requestSubmit): ✅
- d (exclude): ✅
- enter (행 선택 토글): ✅ — 단 의미가 *다음 거래*가 아니라 *선택 토글*
- ?: ✅ (도움말)
- **x (중복 표시): ❌** — 컨트롤러 주석 17행 "x=duplicate)는 후속 슬라이스"
- **cmd/ctrl+enter (전체 반영): ❌**

doc(`_keyboard_shortcuts_help.html.erb`)는 enter를 "선택 토글"로 안내. 즉 매핑 자체가 변경됐는데 로드맵 영향은 supersede 없음 — 결정 트레일이 없음.

### 3.5 직접 `number_to_currency` 호출 30개 파일

`shared/_amount.html.erb`(line 59 `tabular-nums whitespace-nowrap`)는 잘 만들었지만, **30+ 파일이 직접 `number_to_currency(..., unit: '₩', precision: 0)` 호출**. 즉 `_amount` 채택률이 낮음.

대표 예:
- `app/views/transactions/index.html.erb:84` (페이지 합계)
- `app/views/reviews/show.html.erb:45` (총 금액 — `text-2xl font-bold text-action`)
- `app/views/dashboards/calendar.html.erb:13, 100, 144` (월 합계, 일별, 일별 거래)
- `app/views/workspaces/show.html.erb:39` 등

이 중 많은 곳은 *고정 폭 카드* 안이라 자릿수 흔들림이 안 보이긴 하지만, `_amount` 채택 = 통일된 톤(`positive/warning/danger/muted`) + tabular-nums + 후치 단위가 같이 오는 표준이므로 채택률은 디자인 시스템 성숙도 지표.

### 3.6 focus ring 이중 정의

- 글로벌 `:focus-visible` 룰: `application.tailwind.css:168-172`에 `outline: 2px solid var(--color-focus)` ✅
- 인라인 `focus:ring-1 focus:ring-action`도 20+ 파일에 여전히 존재 → cascade 상 inline이 우선
- Phase 5 cleanup 후 정리되지 않은 잔재. 큰 문제는 아니지만 표준이 통일되지 않음.

### 3.7 컨트라스트 자동 감사 없음

ADR-0008 / Phase 5 명시: "컨트라스트 감사 (전체 페이지)"
- 자동화된 axe-core / Lighthouse CI 없음.
- 토큰 페어는 `light-dark()` 정의됨 — 시각 자체는 정의되어 있으나 WCAG AA(4.5:1) 통과 *증거*가 PR 어디에도 없음.

### 3.8 컴포넌트 명세 vs 실제 명명

synthesis §6.1 명명 규칙(`Scene/Section/Card/Row/Chip/Sheet/Modal`)은 코드의 partial 명에 일관 적용:
- `_variance_card`, `_review_inbox_card`, `_recurring_payment_card`, `_transaction_row`, `_category_source_chip`, `_pending_badge`, `_input_sheet`, `_duplicate_modal` — 규칙 OK.
- **단 `Section` 일반화 partial이 없다** — `_category_breakdown`, `_recent_transactions_panel` 같은 게 직접 호출되는데, 6.3의 Section 컴포넌트화 의도와 어긋남.

---

## 4. 🟢 사소한 잔존 / 잡음

### 4.1 _input_sheet의 `_inline_alert` 호출

`shared/_input_sheet.html.erb:63`이 유일한 `_inline_alert` 호출처. AI 동의 카드를 위한 X11 / Value First 카드인데 사용 깊이가 한 곳뿐. 명시적으로 X4 "AI 별도 채널"이 카테고리 추천 / 학습 등 다른 화면으로 확장되어야 했음. 카테고리 학습 suggestion은 `transactions/_category_learning_suggestion_row.html.erb`에서 별도 처리 — 일관 partial이 아님.

### 4.2 transactions/index의 중복 검사 버튼 색

`transactions/index.html.erb:68-74`:
```erb
<button ... class="px-4 py-2 text-sm bg-warning text-action-on rounded-md hover:bg-warning">
```

`bg-warning`(b45309 = brown/orange)에 `text-action-on`(흰색) — 의미축이 살짝 어긋남. CTA가 아닌 warning 색을 버튼 배경으로 쓸 거면 `bg-warning text-action-on` 대신 `border-warning text-warning bg-surface` 같은 secondary 톤이 X5 의도에 더 맞음.

### 4.3 reviews/show의 back link

`reviews/show.html.erb:11`:
```erb
<%= link_to t("reviews.show.back"), workspace_parsing_sessions_path(@workspace) ... %>
```

검토 상세에서 *뒤로가기*가 `parsing_sessions/index`로 향함 — 검토함(`workspace_reviews_path`)이 IA 1번이 되었으면 여기로 와야 자연스러움. 작은 navigation gap.

### 4.4 reviews/index가 _segmented_tabs 인라인 재구현

`reviews/index.html.erb:28-50` — 인라인 segmented tabs (Stimulus controller 별도). _segmented_tabs partial이 만들어졌다면 `<%= render 'shared/segmented_tabs', tabs: [...] %>` 한 줄로 끝났을 것. 다음에 같은 패턴이 또 필요한 화면(거래 [목록 | 캘린더])에서 또 인라인 재구현 위험.

### 4.5 _navbar는 사이드바로 재설계되지 않음

로드맵 §4.4: "layouts/_navbar | 데스크탑 사이드바로 재설계 또는 ContextHeader로 흡수"
- 실제: 상단 nav 유지 (8.2KB 파일). 어느 방향도 채택하지 않음.
- "둘 중 하나"라는 ADR이 명시되지 않음. *결정이 안 된 채 현상 유지*.

### 4.6 부정확한 자체 감사 결과 (서브에이전트 정정)

투입한 컴포넌트 감사 서브에이전트는 다음 partial을 "좀비"로 잘못 판정했었음:
- `_source_icon` — 실제 `shared/transaction_cells/_source_metadata_cell.html.erb:15` 호출됨 ✅
- `_year_picker` — 실제 `dashboards/yearly.html.erb:13` 호출됨 ✅
- `_color_picker` — 실제 `categories/{slideover_form,edit,new}.html.erb`에서 호출 ✅
- `_duplicate_modal`, `_duplicate_card`, `_duplicate_section` — 실제 `transactions/index:216` → `_duplicate_modal`, `reviews/show:70` → `_duplicate_section` → `_duplicate_card:62`로 체인 호출됨 ✅

⇒ 위 컴포넌트들은 살아있음. 다만 로드맵 §4.2가 명시한 "duplicate_confirmations/_row + _modal" *단일화*는 안 됐다(여전히 3개 파일 분산). 즉 "좀비"는 아니지만 "통합 미완료"는 맞음.

---

## 5. 도메인 모델 / 데이터 레이어 점검

| 로드맵 항목 | 상태 |
|---|---|
| `UserSetting#theme` 마이그레이션 | ⚠️ 별도 컬럼 없이 `users.settings` JSON에 저장 (`app/models/user.rb:58-73`). open-questions Q4에서 결정된 사항 — 정당. 다만 명시적 `db/migrate/*_add_theme_to_user_settings.rb` 없음 (마이그레이션 비용 회피 — OK) |
| `Budget` 모델 | ✅ `db/migrate/20260326100001_create_budgets.rb` + `app/models/budget.rb` |
| `RecurringPaymentDetector` | ✅ `app/services/recurring_payment_detector.rb` + `_recurring_payment_card` |
| `ApiKey` 모델 | ✅ `db/migrate/20260326100000_create_api_keys.rb` (Phase A Task 6) |
| `classification_source` | ✅ `db/migrate/20260516022650_add_classification_source_to_transactions.rb` (ADR-0011) |

데이터 모델은 로드맵을 잘 따라간 편. 단 더보기에 `예산` 카드 노출은 되어 있지만 (`workspace_more/show.html.erb`), 홈에서 예산 잔여를 보여주는 hero supporting line은 *조건부*로만 (`dashboards/monthly.html.erb:31-35`) — 그리고 holds in monthly, not the actual /dashboard root.

---

## 6. Phase별 진척 매핑 (commit 기반)

| Phase | 로드맵 의도 | 실제 commit 트레일 | 평가 |
|---|---|---|---|
| Phase 0 (ADR 채택) | 6개 ADR 머지 | 7a60a12 (ADR-0003~0008) + ADR-0010, ADR-0011 추가 채택 | ✅ |
| Phase 1 (토큰 & 코어 partial) | @theme 도입 + screen_shell, context_header, hero_stat | f156d10 (@theme + Pretendard), 1c21721 (core partials + bg-page) | ✅ |
| Phase 2 (거래 컴포넌트 통합) | _transaction_row 단일화 + source_icon/category_source_chip/pending_badge | 329a9d3, 554dc7f, 5835768, 4a6fce3, 8b2ea21, b917aba, 4092f93, 3b4de49 | ✅ |
| Phase 3 (IA 재구성) | reviews/index 신설 + 5탭 + 워크스페이스 스위처 모바일 | b49e608 (reviews/index, workspace_more 동시 등장) — **단 1개 PR** | ⚠️ 골조만, 화면 부품 후속 PR 없음 |
| Phase 4 (Hero & Variance) | hero_stat, variance_card, review_inbox_card 신설 + 홈 재구성 | b49e608에 partial 도입, 그러나 *monthly에 적용*된 게 calendar로 옮기지 않음 | ⚠️ partial은 있고, 홈 위치는 못 옮김 |
| Phase 5 (다크 & a11y) | UserSetting#theme + 컨트라스트 + 키보드 + focus ring | slice 1~22 + cleanup A~D, 총 25+ PR. **가장 큰 집중** | ✅ (단 컨트라스트 자동감사 없음) |
| Phase 6 (카피·i18n) | ko.yml + 모든 view i18n | 6-1 ~ 6-9 + residuals (#244, #245) | ✅ |
| Phase 7 (회고·측정) | 메트릭 비교 (검토 완주율, AI 수용률) | #194, #236~#239, #241, #243. **메트릭 인프라 신설**. 단 baseline 측정 시점과 전후 비교는 없음 | ⚠️ 측정 가능성만, 측정 결과 없음 |

**관찰**:
1. Phase 3-4가 *단 1개 PR(#193 b49e608)*에 합쳐졌다 — 가장 큰 영향의 IA·홈 재구성이 한 PR. commit 메시지가 "policy B + D1 lock"으로, IA 재구성이 부수적으로 들어간 형태.
2. Phase 5는 슬라이스 22개 + cleanup 4개로 **압도적 비중**. 시각 시스템·a11y에 자원이 몰림.
3. Phase 6은 9개 슬라이스 + 2개 residual로 *완성도 추구*.
4. Phase 7은 메트릭 도입은 했으나 *전후 비교 데이터 없음* — §11의 "베이스라인은 Phase 1 시작 직전"이라는 약속은 안 지켜짐.

---

## 7. 우선순위별 권고

### 🔴 P0 (즉시) — 가장 큰 IA / X11 미스 메우기

1. **홈 결정 ADR 작성**:
   - "사용자가 로그인 후 보는 첫 화면은 calendar인가, monthly hero인가" 결정. 둘 중 하나로 align.
   - 권고: monthly의 hero/variance/review-inbox를 calendar 위에 stack하거나, root를 monthly로 옮기고 calendar를 sub.
2. **commit 버튼 UI 게이트**:
   - `reviews/show.html.erb:80-99`에 `@parsing_session.has_unresolved_duplicates?` 체크 후 `disabled` + `risk.commit_locked` 카피 표시.
   - 이미 ko.yml에 카피 있음 — view에 t() 한 줄.
3. **워크스페이스 삭제 2단계 + 이름 입력**:
   - `workspace_more/show.html.erb`의 single confirm → Stimulus 모달로 워크스페이스명 input 매칭 후 활성.

### 🟡 P1 (단기) — 컴포넌트 사전 완성

4. **신설 누락 partial 9개 추가** (가장 큰 영향 순):
   - `shared/_segmented_tabs.html.erb` — reviews/index + dashboards/_tabs를 모두 흡수
   - `shared/_sticky_action_bar.html.erb` — reviews/show의 commit 영역
   - `shared/_empty_state.html.erb` — X7 통일
   - `shared/_risk_notice.html.erb` — X11 마찰 UI 게이트
   - `shared/_chip_scroller.html.erb` + `shared/_filter_sheet.html.erb` — transactions/index 필터 재구성
   - `shared/_workspace_switcher.html.erb` — 추출 + 모바일 헤더 노출
   - `shared/_bottom_sheet.html.erb` — _input_sheet 일반화
   - `shared/_ai_badge_card.html.erb` — 카테고리/검토함 AI 출력
5. **`dashboards/_tabs` 폐기**:
   - `_segmented_tabs` 도입 후 4개 dashboards view에서 `render 'tabs'` 일괄 교체.
6. **모바일 워크스페이스 스위처**:
   - `_mobile_bottom_nav` 위에 sticky 헤더 또는 ContextHeader 안에.
7. **bulk_delete / rollback / workspace_leave에 영향 범위 카피 적용**:
   - 이미 ko.yml 키 있음 — view에서 `t("risk.bulk_delete", count: ..., amount: ...)`로 합계 주입.

### 🟢 P2 (중기) — Polish

8. **`_amount` 전면 채택** — 30개 파일의 직접 number_to_currency 호출 점진 교체.
9. **transactions/index §3.2 명세대로 재구성** — [목록 | 캘린더] SegmentedTabs + ChipScroller + FilterSheet.
10. **reviews/index 본문 채우기** — ParsingSessionCard, DuplicateConfirmationRow.
11. **컨트라스트 자동 감사 CI** — axe-core 또는 Lighthouse CI.
12. **키보드 단축키 x, cmd+enter** 추가 + 로드맵 enter 의미 변경 ADR 또는 카피 수정.
13. **focus ring 인라인 정리** — `:focus-visible` 글로벌 룰로 일원화.
14. **베이스라인 메트릭 측정 데이터 추출** — Phase 7 인프라를 *써서* 검토 완주율 등 비교.

---

## 8. 종합 점수

| 영역 | 가중 | 점수 | 비고 |
|---|---|---|---|
| **인프라 (토큰/다크/i18n/폰트/라우트/메트릭)** | 30% | 92 | 매우 잘 됨 |
| **5탭 IA + 검토함 승격** | 15% | 85 | 라우트·네비 OK, 화면 부품 미완 |
| **시각 시스템 (팔레트→시맨틱)** | 15% | 90 | 광범위 적용, focus ring 잔재 |
| **컴포넌트 사전 (§4.1 신설 20개)** | 15% | 55 | 13개 만들고 7~8개 핵심 누락 |
| **화면 단위 To-Be (홈 §3.1, 거래 §3.2, 검토함 §3.3)** | 15% | 40 | 카드는 만들었지만 홈 위치 안 맞고, 거래·검토함 골조 후속 PR 없음 |
| **X11 의도적 마찰 + 키보드 단축키** | 10% | 35 | 카피 있고 게이트 없음 |
| **종합** | 100% | **~70/100** | 인프라 우수 / 화면 단위 미흡 |

---

## 9. 한 줄 마지막

> 토스 + 뱅샐 분석에서 가져온 *기율*은 잘 코드화됐지만, *화면*은 절반만 다시 그려졌다. **"디자인 시스템 도입"은 끝났고, "디자인 시스템을 쓰는 화면 재구성"은 아직 시작에 가깝다.** Phase 3-4의 후속 슬라이스를 작은 PR로 쪼개 컴포넌트 사전(§4.1) 잔여를 메우고, 그 위에 §3.1~§3.3 To-Be 명세대로 홈/거래/검토함을 다시 짜야 로드맵이 닫힌다.

---

## 부록 — 인용 출처 색인

### 로드맵 문서
- `docs/discovery/2026-05-15-design-system-synthesis.md` (X1~X12, 토큰, 컴포넌트 사전, 8장 카피, 9장 마찰, 11장 통합 인사이트)
- `docs/discovery/2026-05-15-ui-redesign-plan.md` (§1 진단, §3 화면 To-Be, §4 컴포넌트 매핑, §5 토큰, §6 Phase 로드맵)
- `docs/decisions/ADR-0003 ~ ADR-0008, ADR-0010, ADR-0011`

### 핵심 코드 인용 (보고서 본문에서 사용)

**라우트**:
- `config/routes.rb:21, 69, 75, 79, 110, 118`

**홈 / 대시보드**:
- `app/views/dashboards/calendar.html.erb:1-155` (실제 홈)
- `app/views/dashboards/monthly.html.erb:5-89` (Hero/Variance/ReviewInbox 위치)
- `app/views/dashboards/_tabs.html.erb` (폐기 대상 잔존)

**검토함**:
- `app/views/reviews/index.html.erb:1-136` (골조만)
- `app/views/reviews/show.html.erb:11, 70-75, 80-101, 137-142` (back link, duplicate section, commit form, rollback)
- `app/controllers/reviews_controller.rb#commit` (서버 가드)

**거래**:
- `app/views/transactions/index.html.erb:26-90, 192, 216` (인라인 form, transaction_row, duplicate_modal)
- `app/views/parsing_sessions/index.html.erb:7-25` (자가 호환 carve-out)

**Shell / Layout**:
- `app/views/layouts/application.html.erb:7-26, 43`
- `app/views/layouts/_navbar.html.erb:10-89` (5탭 + workspace select)
- `app/views/layouts/_mobile_bottom_nav.html.erb:4-53` (5탭, 스위처 없음)
- `app/views/shared/_screen_shell.html.erb:1-23`
- `app/views/shared/_context_header.html.erb` (저채택)

**토큰 / 다크모드**:
- `app/assets/stylesheets/application.tailwind.css:33-282`
- `app/models/user.rb:58-73` (theme getter/setter)
- `app/views/workspace_more/show.html.erb:50-72, 114-121` (toggle UI, delete confirm)

**키보드**:
- `app/javascript/controllers/review_keyboard_controller.js:1-194`

**카피**:
- `config/locales/ko.yml:risk.*, cta.*, live.*, empty.*, ai.*, learn.*`

**Phase 7**:
- `app/services/import_review_metrics_report.rb`
- `app/views/metrics/sections/_classification_source_distribution.html.erb`

### Git 트레일
- Phase 1: f156d10, 1c21721
- Phase 2: 329a9d3, 554dc7f, 5835768, 4a6fce3, 8b2ea21, b917aba, 4092f93, 3b4de49
- Phase 3-4: b49e608 (단일 PR로 IA + Hero 카드 동시)
- Phase 5: slices 1~22 + cleanup A~D (PRs #199, #200, #202~#218, #219~#224)
- Phase 6: #225, #226~#234 + #244, #245
- Phase 7: #194, #236~#239, #241, #243
