# GPT 적대적 리뷰 원문 (2026-05-19)

> 본 문서는 외부 GPT 리뷰를 **원문 그대로** 보존한다. xef-scale 메인테이너 본인의 비판적 평가와 합리적 반영안은 별도 문서 `docs/discovery/2026-05-19-review-comparison-and-merged-action-plan.md`에서 다룬다.

---

# xef-scale UI 재구성 로드맵 구현 적대적 리뷰

- 리뷰 일자: 2026-05-19
- 대상: `alxdr3k/xef-scale` `main` 기준 정적 소스 리뷰
- 기준 문서: `docs/discovery/2026-05-15-ui-redesign-plan.md`, `ADR-0003~0008`
- 커밋 여부: 없음
- 실행 여부: 로컬 앱/테스트 실행은 하지 않음. GitHub connector로 PR 메타데이터와 main 소스를 읽어 대조했다.

---

## 0. 총평

결론부터 말하면 **"로드맵대로 잘 구현됐다"라고 말하기엔 아직 이르다.**

좋은 쪽으로는 semantic token, 다크모드 기반, i18n 계약, 위험 confirm copy invariant, 검토 상세 키보드 단축키, InputSheet focus trap, `reviews#index`의 workspace scoping 같은 **엔지니어링 안전장치**가 상당히 강하게 들어갔다. 이전에 반복되던 "view만 grep하고 helper/JS/CSS surface를 놓치는" 문제도 contract test로 많이 줄었다.

하지만 적대적으로 보면 현재 상태는 **"색상·카피·검토 상세은 많이 정리됐지만, 토스/뱅샐 분석에서 추출한 IA/컴포넌트/한 화면 한 과업 원칙은 아직 반쪽짜리"**다. 특히 다음 네 축이 미완료다.

1. **홈/IA의 실제 첫 진입 경험**: 인증 root가 `calendar`라서 Phase 4의 Hero/Variance/ReviewInbox가 첫 화면 보장이 아니다.
2. **거래 화면 UX**: 여전히 table + inline filter + duplicate check local button 구조다. ChipScroller/FilterSheet/목록·캘린더 dual view는 선언만 가깝고 실제는 구 UI가 많이 남았다.
3. **컴포넌트 사전 거버넌스**: `ContextHeader`, `HeroStat`, `Amount`는 있으나 핵심 페이지에서 inline h1/p, inline empty state, 기존 `_tabs`가 계속 쓰인다. `SegmentedTabs`, `EmptyState`는 현재 경로에서 확인되지 않았다.
4. **계약 테스트의 blind spot**: semantic token contract가 `gray-900`류는 잘 잡지만 `bg-black/50`, `bg-black/40`, `ring-black` 같은 black/white 계열 토큰 우회를 놓친다.

P0급 즉시 데이터/권한 손상은 현재 읽은 범위에서 발견하지 못했다. 그러나 P1/P2급 제품-로드맵 불일치와 접근성 회귀 가능성은 분명하다.

---

## 1. 구현이 잘 된 부분

### 1.1 Semantic token 및 다크모드 기반

`application.tailwind.css`에 `@theme` 기반 semantic color, typography, radius, shadow, motion token이 들어갔고 `light-dark()` pair도 정의되어 있다. `application.html.erb`는 `<html data-theme="auto|light|dark">`를 세팅하고 Turbo navigation에서도 meta 값을 동기화한다. `ScreenShell`도 `body class="bg-page text-primary"`로 바뀌었다.

이건 로드맵 Phase 1/5의 핵심 기반으로 합격에 가깝다.

### 1.2 Semantic token contract가 넓어짐

`semantic_token_contract_test.rb`는 ERB view, helper-generated HTML, Stimulus dynamic DOM, CSS surface를 모두 검사한다. 팔레트 utility, raw hex/rgb, sed truncation artifact까지 잡으려는 방향은 좋다.

단, 아래 Findings에서 말하듯 black/white 계열과 component-usage에는 blind spot이 있다.

### 1.3 i18n / 위험 카피 회귀 방지

`I18nHardcodedKoreanContractTest`, `HtmlSafeTranslationPolicyTest`, `RiskConfirmCopyInvariantTest`가 들어가 있다. 특히 위험 행동 confirm key를 registry로 관리하고 "되돌릴 수 없음 / 일괄 / 영향 범위" 같은 위험 정보 marker를 검사하는 접근은 좋다.

단, i18n baseline이 아직 file-level이라 일부 허점이 남아 있다.

### 1.4 검토함 index의 권한/scoping 구현

`ReviewsController#index`는 `set_parsing_session`에서 제외되어 있고 read 권한만 요구한다. `ParsingSession.needs_review`를 사용하며, `DuplicateConfirmation`도 `joins(:parsing_session)` + workspace filter + `ParsingSession.needs_review` merge로 cross-tenant leak과 finalized-session 잔여 pending 노출을 피하려 한다.

이건 ADR-0004의 가장 중요한 서버 측 함정을 잘 반영한 구현이다.

### 1.5 InputSheet 접근성 hotfix

`InputSheet`는 `role="dialog"`, `aria-modal="true"`, Esc close, backdrop close, focus restore, Tab focus trap, Turbo cache cleanup을 갖는다. 이전 우려였던 "시트가 뜨지만 focus는 뒤 페이지에 남는 문제"는 현재 코드상 상당히 완화됐다.

### 1.6 Unified transaction row

`transactions/_transaction_row.html.erb`가 transactions/reviews 양쪽에서 쓰이는 단일 row로 정리됐고, review context의 update URL, category request shape, parsing_session_id preservation을 explicit local로 받도록 되어 있다. 이전 category dropdown 우회 문제를 잘 의식한 구조다.

---

## 2. Findings

### P1-1. 5탭 IA가 역할별로 깨진다 — "공통 5탭"이 실제론 admin-only 4/5탭이다

**증상**

ADR-0004는 모바일·데스크탑 공통 5탭 IA를 명시한다: 홈 / 거래 / 검토함 / 카테고리 / 더보기. 그런데 현재 desktop navbar와 mobile bottom nav는 카테고리 탭을 `current_user.admin_of?(current_workspace)`일 때만 렌더한다.

**왜 문제인가**

이건 단순 숨김이 아니라 로드맵의 IA 계약 위반이다. `member_write`나 `member_read` 사용자에게는 하단 탭이 4개가 된다. "모바일과 데스크탑이 동일 5탭"이라는 ADR 문장이 사용자 role에 따라 거짓이 된다.

더 나쁘게는, 카테고리/매핑은 가계부의 해석 체계다. read/write 멤버가 카테고리 체계를 못 보는 것이 의도라면 ADR이 틀린 것이고, 의도가 아니라면 nav 구현이 틀린 것이다.

**권고**

둘 중 하나로 결정해야 한다.

- 제품 결정 A: 카테고리를 모든 read 이상 사용자에게 read-only로 노출한다. 생성/수정만 admin gate.
- 제품 결정 B: 5탭 IA를 "admin 5탭 / non-admin 4탭"으로 공식 변경하고 ADR-0004, ui-redesign-plan, nav comment, 테스트를 모두 수정한다.

현재처럼 "주석은 5탭, 구현은 role-adaptive" 상태로 두면 다음 리뷰/PR에서 계속 혼선이 난다.

---

### P1-2. 인증 후 root가 calendar라서 Phase 4 Home Hero/Variance/ReviewInbox가 첫 화면이 아니다

**증상**

`config/routes.rb`에서 authenticated root는 `dashboards#calendar`다. 반면 Phase 4의 `HeroStat`, `VarianceCard`, `ReviewInboxCard`, `RecurringPaymentCard`는 `dashboards/monthly.html.erb`에 적용되어 있다.

**왜 문제인가**

로드맵의 홈 정의는 "이번 달 지출 hero → variance → review pressure → category breakdown → recurring"였다. 하지만 사용자가 로그인 후 실제 처음 보는 건 calendar page다. calendar page는 월 합계와 quick-filter badge를 보여주지만, HeroStat/Variance/ReviewInboxCard의 행동 압력은 없다.

즉 "홈을 갈아엎었다"가 아니라 "월간 탭을 갈아엎었다"에 가깝다.

**추가 문제**

calendar의 검토/중복 quick badge는 `workspace_parsing_sessions_path`로 보낸다. ADR-0004는 검토함을 IA 1번 시민으로 승격했는데, 첫 화면의 행동 badge가 여전히 입력 기록/옛 path로 보내는 셈이다.

**권고**

- 선택 A: authenticated root를 monthly/home으로 돌리고 calendar는 segmented tab의 하나로 둔다.
- 선택 B: calendar를 진짜 홈으로 삼되, Hero/Variance/ReviewInbox/Recurring을 calendar 상단에도 통합한다.
- 선택 C: calendar default는 유지하되 ADR/roadmap의 "홈" 정의를 "calendar-first home"으로 개정한다.

현 상태는 사용자 대화에서 "다른 가계부 앱은 캘린더 default"라는 관찰과 Phase 4 home roadmap이 충돌한 결과로 보인다. 이 충돌을 문서로 정리하지 않으면 계속 애매해진다.

---

### P1-3. 거래 화면은 아직 구 UI다 — ChipScroller/FilterSheet/한 화면 한 과업이 미구현

**증상**

`transactions/index.html.erb`는 여전히 다음 구조다.

- inline `<h1>`/`<p>` header
- inline year/month/category/search form
- duplicate check button
- summary card
- bulk toolbar
- table layout

로드맵은 거래 화면을 `ContextHeader`, `SegmentedTabs [목록|캘린더]`, `ChipScroller`, `FilterSheet`, `DateGroupHeader`, `TransactionRow`, mobile FAB 중심으로 재구성하라고 했다.

**왜 문제인가**

거래 화면은 사용자가 가장 오래 머무는 surface다. 여기서 구 UI가 남으면 전체 개편의 체감이 급격히 낮아진다. 특히 모바일에서 table + inline filter는 Toss/Banksalad 분석의 핵심인 "한 화면 한 과업", "터치 밀도 최소화", "필터는 chip/sheet로 분리"와 어긋난다.

**권고**

거래 화면은 다음 PR의 최우선 후보가 맞다.

1. inline filter form을 `FilterSheet`로 추출.
2. 현재 적용 filter는 `ChipScroller`로 요약.
3. desktop table은 유지하더라도 mobile은 card/list row로 분리.
4. duplicate check는 거래 toolbar에서 제거하거나 "검토함 > 중복 후보"로 보낸다.
5. `ContextHeader`를 적용해 workspace name만 반복 노출하지 말고 기간 합계/필터 상태를 live context로 보여준다.

---

### P1-4. 컴포넌트 사전이 "존재"는 하지만 "지배"하지 못한다

**증상**

다음 상태가 동시에 존재한다.

- `shared/_context_header.html.erb`는 존재한다.
- 하지만 `transactions/index`, `reviews/index`, `reviews/show`, `dashboards/monthly`, `dashboards/calendar`, `categories/index`, `workspace_more/show` 등 주요 화면은 여전히 inline h1/p를 직접 쓴다.
- `shared/_hero_stat.html.erb`, `shared/_amount.html.erb`는 존재한다.
- 하지만 여러 화면에서 `number_to_currency`를 직접 호출한다.
- `dashboards/_tabs.html.erb`는 여전히 존재한다.
- `shared/_segmented_tabs.html.erb`는 현재 경로에서 확인되지 않았다.
- `shared/_empty_state.html.erb`도 현재 경로에서 확인되지 않았고, 실제 화면은 inline empty state를 쓴다.

**왜 문제인가**

ADR-0003은 Product Language와 component governance를 채택했다. 그런데 현재는 "몇 개 좋은 partial이 생겼다" 수준이지 "화면 생성 방식이 component catalog에 의해 지배된다" 수준은 아니다.

이 상태가 길어지면 다음 현상이 생긴다.

- 새 화면이 또 inline header/empty state를 복사한다.
- 기존 page별 radius/shadow/spacing 편차가 다시 생긴다.
- 디자인 리뷰가 "문서상 컴포넌트"와 "실제 구현" 중 무엇을 기준으로 해야 하는지 애매해진다.

**권고**

Phase 7 이후 첫 hardening PR로 "component adoption contract"를 걸어야 한다.

- 핵심 화면은 반드시 `ContextHeader`를 render한다.
- dashboard tabs는 `SegmentedTabs`로 흡수하고 `_tabs`를 삭제한다.
- empty state는 `shared/empty_state` 외 직접 구현 금지.
- amount 표기는 `shared/amount` 또는 helper 외 직접 `number_to_currency` 사용 금지.

정적 테스트가 너무 빡세면 최소한 "대상 파일 allowlist를 줄여가는 계약"으로 시작한다.

---

### P1-5. Semantic token contract가 black/white 계열을 놓친다

**증상**

semantic token contract는 `gray/slate/indigo/red/... + 숫자` 형태의 Tailwind palette utility는 잘 잡는다. 하지만 다음 패턴은 현재 남아 있다.

- `bg-black/50` in `transactions/_duplicate_modal.html.erb`
- `bg-black/40` in `shared/_input_sheet.html.erb`
- `ring-black ring-opacity-5` in `layouts/_navbar.html.erb`

**왜 문제인가**

로드맵의 token set에는 이미 overlay 의미축이 있다. backdrop은 `bg-overlay` 같은 semantic token으로 가야 한다. black/white는 숫자 suffix가 없어서 contract test를 우회한다. 그러면 팀은 "semantic token contract가 있다"고 믿지만, 가장 흔한 modal/dropdown overlay 계층은 계속 raw color로 남는다.

**권고**

1. `--color-overlay`를 Tailwind utility로 사용하게 하고 `bg-black/40`, `bg-black/50`을 `bg-overlay`로 교체.
2. dropdown ring은 `ring-edge`, `ring-divider`, `border-divider` 등으로 바꾼다.
3. contract regex에 `black|white` 계열을 추가한다. 예: `bg-black`, `bg-white`, `text-black`, `text-white`, `ring-black`, `ring-white`, opacity suffix 포함.
4. allowlist가 필요하면 file 전체 allowlist가 아니라 line-level marker를 쓴다.

---

### P1-6. Navbar의 `focus:outline-none`가 global focus ring을 죽일 수 있다

**증상**

`application.tailwind.css`에는 `:focus-visible` global outline rule이 있다. 그런데 `_navbar.html.erb`의 help button, notification button 등에 `focus:outline-none`이 붙어 있고 대체 `focus:ring-*`이 없다. search 결과도 이 패턴은 navbar에 집중되어 있다.

**왜 문제인가**

Tailwind utility는 클래스 specificity가 있고 global base rule은 `:where(...)`라 specificity가 낮다. `focus:outline-none`가 실제 focus-visible outline을 이길 가능성이 높다. profile button처럼 `focus:ring-2`가 같이 있으면 괜찮지만, help/notification은 그렇지 않다.

**권고**

- `focus:outline-none` 제거.
- 불가피하면 같은 element에 `focus-visible:ring-2 focus-visible:ring-focus` 또는 equivalent를 명시.
- contract test 추가: `focus:outline-none`가 있는 interactive element는 같은 class 안에 `focus:ring|focus-visible:ring|focus-visible:outline` 중 하나가 있어야 한다.

---

### P1-7. 중복 UI 통합이 안 됐다 — duplicate decision language가 두 갈래다

**증상**

로드맵은 `transactions/_duplicate_modal` + `reviews/_duplicate_card` + `_duplicate_section`을 단일 `duplicate_confirmations/_row` + `_modal`로 통합하라고 했다. 현재는 다음이 모두 남아 있다.

- `transactions/_duplicate_modal.html.erb`
- `reviews/_duplicate_card.html.erb`
- `reviews/_duplicate_section.html.erb`

**왜 문제인가**

중복 처리는 장부 총액을 바꾸는 위험한 결정이다. 거래 목록의 "중복 검사 modal"과 검토 상세의 "중복 후보 card/section"이 별도 UI면 다음 위험이 생긴다.

- keep_original / keep_new / keep_both의 설명·위험 카피가 달라진다.
- keyboard affordance가 달라진다.
- analytics/metrics에서 같은 행동을 다르게 해석할 수 있다.
- 하나만 hotfix되고 다른 하나가 stale해진다.

**권고**

`duplicate_confirmations/_row.html.erb`를 만들고, 두 surface가 같은 row/decision button/copy partial을 쓰도록 줄인다. 거래 목록의 duplicate modal은 "standalone duplicate confirmation session"을 렌더하는 wrapper로만 남기는 편이 안전하다.

---

### P2-1. Review index는 "진입로"는 됐지만 "작업면"은 아니다

**증상**

`reviews/index.html.erb`는 pending sessions와 duplicate confirmations를 tab으로 보여주고, 세부 검토는 `review_workspace_parsing_session_path`로 보낸다. 로드맵의 To-Be는 parsing result tab에서 `TransactionRow × N`, duplicate tab에서 3-way duplicate decision row, sticky action bar까지 제안했다.

**왜 문제인가**

지금 구현은 IA 승격이다. 하지만 사용자가 실제 검토를 완료하려면 여전히 세션 상세로 들어가야 한다. 즉 "검토함이 1급 시민"은 맞지만 "검토 워크플로우가 한 화면에서 처리된다"는 로드맵 수준에는 못 미친다.

**권고**

두 가지 중 하나를 선택한다.

- 더 야심찬 길: index에서 pending session expand row를 열어 inline review를 가능하게 한다.
- 더 보수적 길: ADR/roadmap을 "index는 queue/list, 실제 workbench는 show"로 수정한다.

현재처럼 문서는 workbench, 구현은 queue면 기대치가 어긋난다.

---

### P2-2. More page는 생겼지만 로드맵의 More 정보구조보다 작다

**증상**

`workspace_more/show`는 워크스페이스 정보, 설정, 스위치, 테마, 계정 설정, 알림, 용돈, metrics, 삭제, 로그아웃을 제공한다. 하지만 로드맵의 More는 멤버, 초대 링크, 예산, AI 설정 toggle, 언어, API 키, 도움말까지 그룹화했다.

**왜 문제인가**

더보기는 "잡동사니"가 아니라 IA overflow를 관리하는 안전장치다. 지금은 일부 핵심 관리 진입점이 navbar/user menu/별도 settings에 남아 있을 가능성이 높고, More 자체가 아직 완성된 information architecture가 아니다.

**권고**

- More page를 "전용 entry hub"로 만들지, "일부 빠른 링크"로 둘지 결정한다.
- 전용 hub라면 멤버/초대/예산/AI 설정/도움말을 모두 같은 그룹 언어로 가져와야 한다.
- 아니라면 로드맵의 §3.5를 축소해 stale claim을 없앤다.

---

### P2-3. 카테고리 화면은 통합됐지만 Product Language 수준은 아직 낮다

**증상**

카테고리와 학습된 매핑은 같은 page의 두 section으로 합쳐졌다. 이건 좋다. 하지만 여전히 table 중심이며 `ContextHeader`를 쓰지 않고, AI 추천 카드(`AIBadgeCard`)도 보이지 않는다. nav도 admin-only로 감춰진다.

**왜 문제인가**

로드맵상 카테고리는 단순 admin 설정이 아니라 "사용자와 AI가 공유하는 분류 언어"다. 그런데 구현은 아직 설정 테이블에 가깝다. 특히 non-admin에게 숨기는 순간, 공유 가계부의 분류 언어가 관리자 전용 backstage가 된다.

**권고**

- read-only category overview를 모든 멤버에게 노출할지 결정.
- category/mapping rows를 card/list 형태로 바꿔 mobile consumption을 개선.
- AI 추천 카드를 넣거나 명시적으로 deferred 처리.

---

### P2-4. Amount partial은 있는데 금액 표기가 아직 직접 호출로 흩어진다

**증상**

`shared/_amount.html.erb`는 존재하지만 주요 화면은 여전히 직접 `number_to_currency`를 호출한다. 예: dashboard calendar total, review stat amount, duplicate card amount, recurring payment card amount 등.

**왜 문제인가**

로드맵은 모든 금액을 `tabular-nums`, tone, size, sign policy로 통일하라고 했다. 직접 호출이 흩어지면 다음이 깨진다.

- 원/₩ prefix/postfix 정책
- 수입/지출/경고 tone
- tabular 숫자 정렬
- 다크모드 대비
- skeleton/loading 상태 확장

**권고**

- view에서 `number_to_currency` 직접 호출 금지 계약을 걸고, `_amount` 또는 helper로 수렴.
- 예외는 CSV/export/email 같은 비-UI surface만 allowlist.

---

### P2-5. MonthNav/SegmentedTabs/EmptyState가 아직 흡수되지 않았다

**증상**

로드맵은 `shared/_month_nav`, `shared/_segmented_tabs`, `shared/_empty_state`를 제안했고 `dashboards/_tabs` 폐기를 명시했다. 현재 monthly/calendar는 month navigation을 inline으로 두고, dashboard는 기존 `_tabs`를 유지한다. Empty state도 거래/검토/입력기록/카테고리에서 각자 inline으로 구현한다.

**왜 문제인가**

이건 작은 미관 문제가 아니라 Product Language의 부재다. 페이지마다 같은 상태를 다르게 말하면 사용자는 "같은 구조"로 학습하지 못한다.

**권고**

- `SegmentedTabs`: dashboard tabs, review tabs, transaction list/calendar tabs에 공통 적용.
- `MonthNav`: monthly/calendar 공통 적용.
- `EmptyState`: title/body/action/tone 구조로 모든 빈 상태 통합.

---

### P2-6. i18n hardcoded Korean contract의 baseline이 아직 file-level이다

**증상**

`I18nHardcodedKoreanContractTest`는 baseline 파일로 `app/views/pages/landing.html.erb`, `app/views/shared/_context_header.html.erb`를 남겨 둔다. 이 파일 안에서는 새 한글 리터럴이 추가되어도 file-level baseline 때문에 잡히지 않을 수 있다.

**왜 문제인가**

Phase 6의 목표는 "copy가 product language로 중앙화되는 것"이다. file-level baseline은 임시 완충으로는 괜찮지만 오래 두면 정확히 그 파일들이 "새 하드코딩의 쓰레기통"이 된다.

**권고**

- baseline을 line-count 또는 exact-line baseline으로 바꾼다.
- `_context_header` 안 예시/한글 comment를 제거하거나 i18n-allow line marker로 축소한다.
- landing은 gradient/trade dress 예외와 i18n 예외를 분리 관리한다.

---

### P2-7. Calendar quick filters가 검토함이 아니라 입력 기록으로 보낸다

**증상**

calendar page의 needs_review / duplicate badges는 `workspace_parsing_sessions_path(... filter: ...)`로 링크한다. ADR-0004에 따르면 검토함 인덱스가 새 1급 IA다.

**왜 문제인가**

사용자는 "검토 대기"를 누르면 검토함으로 가야 한다. 입력 기록으로 가면 과거 IA가 계속 살아난다. `/parsing_sessions`는 호환 경로로 유지할 수 있지만, 새 surface에서 행동 CTA가 옛 경로를 가리키는 건 로드맵과 반대다.

**권고**

- calendar quick badge를 `workspace_reviews_path`로 보낸다.
- 필요하면 query param `tab=sessions|duplicates`, `year`, `month`를 reviews index가 받게 한다.

---

### P3-1. Review active-state regex에 죽은 분기가 있다

**증상**

nav active state가 `request.path.match?(/\/reviews\z|\/reviews\?|\/parsing_sessions/)` 형태다. `request.path`에는 query string이 없으므로 `/reviews\?`는 사실상 의미가 없다.

**왜 문제인가**

현재 치명적 기능 오류는 아니지만, IA 전환 중 copy-paste 조건이 부정확해지고 있다는 신호다. trailing slash, query param, nested review path 같은 edge에서 active state가 어긋날 수 있다.

**권고**

- path helper 또는 controller/action 기반 active helper를 만든다.
- 문자열 regex를 navbar/mobile bottom nav 양쪽에서 중복하지 않는다.

---

## 3. 로드맵 항목별 판정표

| 로드맵 항목 | 현재 판정 | 메모 |
|---|---:|---|
| ADR-0003~0008 채택 | 통과 | 문서화와 implementation comment가 많음 |
| ScreenShell | 통과 | `shared/screen_shell` 적용 |
| Semantic tokens | 대체로 통과 | black/white 계열 contract blind spot 존재 |
| Dark mode | 대체로 통과 | `User#settings[theme]` 결정은 ADR-0008 후속으로 정합 |
| Unified transaction row | 통과 | context-aware URL/request shape 반영 |
| SourceIcon / CategorySourceChip | 통과 | AI/mapping/keyword distinction 존재 |
| Review index route | 통과 | scoping/permission 함정 반영 |
| Review index workbench | 미완료 | queue/list 수준, inline workbench 아님 |
| 5-tab IA | 부분 통과 | admin-only category 때문에 non-admin은 4탭 |
| More page | 부분 통과 | 전용 page는 있으나 roadmap 정보구조 축소 |
| Home Hero/Variance/ReviewInbox | 부분 통과 | monthly에는 구현, root calendar에는 미적용 |
| Recurring payment card | 통과 | monthly에 적용 |
| 거래 화면 filter/sheet/chips | 미완료 | inline form/table 유지 |
| SegmentTabs 일반화 | 미완료 | dashboard `_tabs` 유지, shared partial 미확인 |
| EmptyState 통합 | 미완료 | inline empty states 유지 |
| Duplicate UI 통합 | 미완료 | transaction modal / review section/card 분리 |
| i18n migration | 대체로 통과 | baseline file-level 잔여 |
| Risk copy invariant | 통과 | destructive confirm registry 존재 |
| Metrics Phase 7 | 대체로 통과 | dashboard/CSV/date validation 구현, 사용자 피드백 수집은 별도 |

---

## 4. 다음 작업 권고

### 4.1 다음 PR 제목 추천

`fix(ui-roadmap): lock IA/component contracts and finish transaction surface`

### 4.2 이 PR에 넣을 우선순위

1. **token blind spot fix**
   - `bg-black/*`, `bg-white`, `text-black`, `text-white`, `ring-black`, `ring-white` 금지.
   - `bg-overlay`, `ring-edge` 등 semantic replacement 적용.

2. **focus-visible contract**
   - `focus:outline-none` 단독 사용 금지.
   - navbar help/notification button 수정.

3. **IA 결정 확정**
   - non-admin category tab을 보여줄지, role-adaptive 4/5 tab으로 문서를 바꿀지 결정.
   - calendar가 root면 Phase 4 Home 정의를 calendar-first로 수정하거나 Hero/ReviewInbox를 calendar 상단에 통합.

4. **component adoption pass**
   - `ContextHeader`를 transactions/reviews/categories/more/dashboard에 적용.
   - `SegmentedTabs`를 신설하고 dashboard/reviews tabs 흡수.
   - `EmptyState` 신설 후 inline empty state 제거.
   - `Amount` usage 확대.

5. **거래 surface 재구성**
   - inline filters → FilterSheet/ChipScroller.
   - mobile row/cards 정리.
   - duplicate check → reviews duplicate tab으로 이동 또는 wrapper 유지 결정.

### 4.3 지금 당장 defer해도 되는 것

- Review index에서 모든 inline review를 구현하는 것: 크다. 먼저 "queue/list"로 공식화하거나 workbench 구현을 별도 milestone으로 분리해도 된다.
- More page의 모든 항목 완성: 핵심 IA 안정화 후 가능. 단 문서에는 deferred로 명시해야 한다.
- ViewComponent 도입: 현 단계에서 불필요. partial governance로 충분하다.

---

## 5. 내 리뷰에 대한 적대적 재검토

내가 위에서 과하게 본 가능성도 있다.

1. **Strangler Fig 전략상 partial이 일부만 쓰이는 건 정상이다.**
   맞다. 하지만 Phase 7까지 갔다면 "일부 도입"을 "로드맵 구현 완료"라고 부르면 안 된다. 현재는 partial 존재와 실제 usage 사이의 간극이 너무 크다.

2. **카테고리 admin-only는 의도적 권한 정책일 수 있다.**
   그럴 수 있다. 그렇다면 finding은 "구현 버그"가 아니라 "ADR/roadmap 거짓말"이다. 둘 중 하나를 고쳐야 한다는 결론은 유지된다.

3. **calendar root는 사용자의 최근 제품 판단일 수 있다.**
   맞다. 사용자가 "다른 가계부는 캘린더 default"라고 본 뒤 calendar-first를 택했을 수 있다. 그렇다면 Phase 4 home spec을 calendar-first로 개정해야 한다. 문서와 구현이 갈라진 상태가 문제다.

4. **`bg-black/50` overlay는 실무적으로 별 문제 없어 보일 수 있다.**
   미관상 문제는 작다. 하지만 token contract가 "semantic only"를 선언한 상황에서는 blind spot이다. `--color-overlay`가 이미 있는데 raw black을 쓰는 건 계약 테스트의 신뢰도를 깎는다.

5. **Review index workbench까지 요구하는 건 scope creep일 수 있다.**
   동의한다. 그래서 권고는 "구현하라"가 아니라 "문서를 queue/list로 낮추거나 별도 milestone으로 분리하라"다.

최종적으로 내 리뷰를 다시 공격해도 결론은 유지된다. 현재 구현은 **semantic/i18n/a11y hardening은 강하고, IA/component/product-language 완성도는 아직 중간 단계**다. 다음 작업은 새 기능보다 "로드맵과 구현의 계약 정합성"을 잠그는 쪽이 맞다.

---

## 6. 한 줄 결론

**색과 카피는 많이 이겼고, IA와 컴포넌트는 아직 이기지 못했다.** 다음 PR은 예쁜 UI 추가가 아니라, `root/home`, `5-tab role policy`, `transaction filter UX`, `SegmentedTabs/EmptyState/Amount/ContextHeader adoption`, `black/white token blind spot`, `focus:outline-none`를 잠그는 hardening이어야 한다.
