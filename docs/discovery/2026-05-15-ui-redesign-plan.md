# xef-scale UI 재구성 실행 계획

- 일자: 2026-05-15
- 입력: `2026-05-15-design-system-synthesis.md` (토스+뱅샐 종합 결과: 원칙 X1~X12, 토큰, Product Language, 5탭 IA)
- 산출물: 현재 UI 진단 + 화면별 재구성 명세 + 단계별 로드맵 + 마이그레이션 전략
- 범위: 본 문서는 **실행 계획**이며 디스커버리이다. 채택된 결정은 `docs/decisions/ADR-0003~ADR-0008`로 별도 승격.

---

## 1. 현재 UI 진단 (As-Is)

### 1.1 IA 진단

| 위치 | 데스크탑 | 모바일 | 문제 |
|---|---|---|---|
| 1번 메뉴 | 대시보드 | 대시보드 | 변동 카드·검토 진입 없음 |
| 2번 메뉴 | 결제 내역 | 결제 | 어휘 부정확("결제 내역") |
| 3번 메뉴 | 가져오기 | 가져오기 | 검토 워크플로우가 묻혀 있음 |
| 4번 메뉴 | 용돈 | — | 데스크탑/모바일 불일치 |
| 5번 메뉴 | — | 설정 | 워크스페이스 진입로 없음 (모바일) |
| 우상단 | 알림 / 워크스페이스 스위처 / 사용자 메뉴 | — | 모바일에서 워크스페이스 스위처 부재 |

### 1.2 시각 시스템 진단

| 항목 | 현재 | 진단 |
|---|---|---|
| 컬러 의미축 | `indigo-600`이 CTA·링크·활성 탭·hero 모두 (`dashboards/monthly.html.erb` hero block) | X5 위반. 사용자가 "지금 누를 것"을 색으로 식별 불가 |
| 라이트/다크 | `body class="bg-gray-50"` 하드코딩 (`application.html.erb`) | 다크 모드 토글 자체가 불가능 |
| 토큰화 | 모든 색이 Tailwind 유틸리티 클래스 인라인 (`text-gray-900`, `bg-indigo-600`) | X14 미적용. 시맨틱 토큰 부재 |
| 폰트 | 시스템 폰트 (별도 지정 없음) | OK — Pretendard 도입은 ADR-0003로 |
| 라운드 | `rounded-lg` (8px) / `rounded-2xl` (16px) 혼용 | 토큰화 필요 |

### 1.3 컴포넌트 진단

현재 partial 분포:

| 분야 | partial | 진단 |
|---|---|---|
| 거래 행 | `transactions/_transaction_row` + `reviews/_transaction_row` | **중복**. 같은 도메인 객체에 두 partial. X12 위반 |
| 카테고리 | `categories/_category_row` + `categories/_slideover_form` | OK 구조 |
| 매핑 | `category_mappings/_mapping_row` + `category_mappings/_slideover_form` | OK 구조 |
| 거래 폼 | `transactions/_form` + `transactions/_edit_modal` + `transactions/_duplicate_modal` | 모달과 폼 분리 — OK |
| 검토 | `reviews/show.html.erb` + `_duplicate_card` + `_duplicate_section` | OK 구조이나 IA에서 묻힘 |
| 가져오기 | `parsing_sessions/index.html.erb` (3-way 입력) + `_parsing_session_card` + `_parsing_session_row` | **재구성 필요**: 입력과 검토가 한 IA에 |
| 빈 상태 | 없음 (각 페이지 인라인) | X7 위반 — 통일된 EmptyState 필요 |
| 컨텍스트 헤더 | `<h1>` + `<p>` 하드코딩 | X3 라이브 컨텍스트 미구현 |
| Hero | `dashboards/monthly` 인디고 그라데이션 block | 시맨틱 토큰화 필요 |

### 1.4 카피 진단

`grep`으로 본 하드코딩된 한글 카피 (예시):
- `결제 내역` (`transactions/index`, navbar)
- `결제 추가` / `+ 결제 추가`
- `AI 파싱`
- `결제 검토`
- `텍스트 붙여넣기`
- `중복 검사`
- `대시보드`
- `용돈`
- `워크스페이스 설정`

→ X10 위반. `ko.yml`로 추출 필요. 동일 의미에 다른 표현 혼용("결제"/"거래"/"내역") 정리 필요.

### 1.5 워크플로우 단절

- `parsing_sessions/index` → 입력 시트 + 세션 목록이 한 화면에 — 입력과 검토가 섞임
- 검토 진입은 세션 카드를 클릭해야 함 — *검토 대기 N건* 정보가 IA 1번 레벨에 안 보임
- `duplicate_confirmations` 결정 흐름이 `reviews/show` 안에 묻혀 있음 — 별도 진입 없음

---

## 2. 어휘 정리 (As-Is → To-Be)

X10에 따라 `ko.yml`로 옮길 핵심 어휘 매핑 표:

| As-Is | To-Be | 적용 위치 |
|---|---|---|
| 결제 내역 | 거래 | navbar, transactions/index, breadcrumb |
| 결제 추가 | 거래 기록하기 | transactions/new CTA |
| 결제 | 거래 | 모바일 하단 탭 |
| 가져오기 | 검토함 (또는 검토) | 모바일·데스크탑 탭 |
| AI 파싱 | 문자로 추가 / 스크린샷으로 추가 | parsing_sessions 입력 CTA |
| 결제 검토 | 거래 검토 | reviews/show |
| 중복 검사 | 중복 후보 보기 | transactions/index toolbar (검토함으로 이동) |
| 외부 AI 사용 안내 | AI 동의 (Value First 카드) | workspace 첫 진입 |
| 워크스페이스 설정 | 워크스페이스 (더보기 안) | 모바일 더보기 |
| 결제 취소 | (유지) | 거래 row 상태 |

전체 i18n 키 사전은 `synthesis.md 8장` 참조.

---

## 3. 화면별 재구성 명세 (To-Be)

### 3.1 홈 (`/dashboard` → `/`)

```
ContextHeader
├ 좌측: "홈" + 라이브 컨텍스트 "{이번달 페이스 ±%}"
└ 우측: 워크스페이스 스위처 · 알림 (🔔 + count) · 더보기 (🔆)

MonthNav  [< 5월 >]   ← 이전/다음 + month picker

HeroStat
├ "이번 달 지출" (라벨, text-secondary)
├ {amount} (display, tabular-nums)
└ 보조: "예산 잔여 {amount}원" + CTA "예산 조정"

VarianceCard   ← 신규
├ "지난달 같은 시점 대비"
├ ▼ {percent}%   (positive/warning 톤)
├ "예상 마감 약 {amount}원"
└ CTA "상세 보기 →"

ReviewInboxCard   ← N > 0일 때만 노출
├ ⚠️ "검토 대기 {count}건 · 중복 {count}건"
└ CTA "지금 검토 →"

Section "카테고리별 지출"
├ Top 5 CategorySourceChip rows (% 막대 포함)
└ CTA "전체 보기"

Section "반복 결제"   ← RecurringPaymentDetector 결과
├ Row × N (결제명 / 다음 결제일 / 금액)
└ CTA "관리"
```

**현재 → To-Be 매핑**:
- 현재 `dashboards/monthly.html.erb` hero block(인디고 그라데이션) → `HeroStat` partial로 추출. 그라데이션 제거, 토큰 사용
- 현재 `_category_breakdown` → `Section "카테고리별 지출"`에 통합
- 새로 추가: `VarianceCard`, `ReviewInboxCard`, `RecurringPaymentCard`
- 탭 (`_tabs.html.erb`) 폐기 → 월/연/달력은 별도 라우트나 `SegmentedTabs`

### 3.2 거래 (`/workspaces/:id/transactions`)

```
ContextHeader  "거래" + 라이브 "{보고 있는 기간 합계}"

SegmentedTabs  [목록 | 캘린더]

ChipScroller   (카테고리 · 금융기관 · 소스 · 상태 · 결제수단)
   ↑ 클릭하면 FilterSheet 진입 (현재 인라인 form 폐기)

Toolbar  [🔍 검색] [+ 기록하기]   ← Floating fab (모바일)

(목록 뷰)
DateGroupHeader sticky   {날짜 + 요일 + 그날 합계}
├ TransactionRow × N
│   • {pending dot, pending_review일 때만}
│   [SourceIcon: ✍/💬/📷/🔗]  [icon]  {가맹점}            {-amount}원
│                                     {CategorySourceChip} · {결제수단}

(캘린더 뷰)
CalendarGrid   (셀별 +/- 합계, 무지출일 마커)
```

**현재 → To-Be 매핑**:
- 현재 `transactions/index.html.erb`의 필터 블록(연도/월/카테고리/검색 인라인 form) → `ChipScroller` + `FilterSheet` 분리. 필터 chip 클릭 → 시트 진입
- 현재 `_transaction_row` → 표준 `TransactionRow`로. `reviews/_transaction_row`와 통합
- `+ 결제 추가` 버튼 → `+ 기록하기`로 어휘 변경, 입력 시트는 3-way (수기/SMS/이미지) 탭
- 중복 검사 버튼 → 검토함 탭으로 이동

### 3.3 검토함 (`/workspaces/:id/reviews` — IA 1번 시민화)

```
ContextHeader  "검토" + 라이브 "{거래 N건 · 중복 M건}"

SegmentedTabs  [파싱 결과 N | 중복 후보 M]

+ 새로 가져오기   ← 우상단 액션 (시트 진입: 3-way)

(파싱 결과 탭)
ParsingSessionCard × N
├ 헤더: [SourceIcon] {파일명 또는 "문자 붙여넣기"} · {시간}
├ 메타: {N건 파싱 · 중복 M건 의심 · 상태 badge}
├ 미리보기: [원본 이미지 보기] / [원본 텍스트 보기]
├ TransactionRow × N (인라인 편집)
└ 행 액션: [반영 N건] [폐기]

(중복 후보 탭)
DuplicateConfirmationRow × N
├ 좌: 기존 거래
├ 우: 신규 거래
└ 3-way 선택: [둘 다 유지 | 기존 유지 | 신규 유지]

RiskNotice   ← 미해결 중복이 있고 commit 시도 시
"중복 {count}건을 먼저 정리해야 반영할 수 있어요"

StickyActionBar
├ secondary "취소"
└ primary "거래 내역 반영 ({count}건)"   ← 미해결 중복 있으면 비활성 + 사유 명시
```

**핵심 변화**:
- 현재 `parsing_sessions/index`는 입력(3-way 시트) + 세션 목록이 같이 있어 검토 진입이 두 단계 — 분리.
- 신규 라우트 `GET /workspaces/:id/reviews` (인덱스). 기존 `reviews/show`는 `GET /workspaces/:id/reviews/:session_id`로 변경하거나 세션별 진입.
- 키보드 단축키 도입 (데스크탑): `j/k/c/d/x/enter/cmd+enter`.

### 3.4 카테고리 (`/workspaces/:id/categories`)

```
ContextHeader  "카테고리" + 라이브 "{N개 · 학습된 매핑 M건}"

Section "내 카테고리"
├ CategoryRow × N  (chip · 키워드 미리보기 · 적용된 거래 수 · chevron)
└ CTA "+ 카테고리 추가"   → Slideover form (기존 partial 재활용)

Section "학습된 매핑"
├ CategoryMappingRow × N
│   {가맹점} → {카테고리}  · {source badge: mapping/keyword/gemini/manual} · {마지막 적용일}
└ CTA "전체 보기"

AIBadgeCard "AI가 추천하는 새 카테고리"
└ Gemini 후보 + 신뢰도 + 채택/거부 액션
```

**현재 → To-Be 매핑**:
- 현재 `categories/index` + `category_mappings/index` → 한 화면에 통합 (Section 분리). 카테고리와 매핑은 짝.
- `_slideover_form`은 그대로 재활용 가능.

### 3.5 더보기 (`/workspaces/:id/more` — 신규)

```
ProfileRow  {워크스페이스명} · {역할 chip}

GroupedListCard "이 워크스페이스"
├ 멤버 · {N}명 ›
├ 초대 링크
└ 예산

GroupedListCard "AI 설정"
├ 텍스트 파싱 ✨ {toggle}
├ 이미지 파싱 ✨ {toggle}
└ 카테고리 추천 ✨ {toggle}

GroupedListCard "내 계정"
├ 알림
├ 화면 테마 (auto / light / dark)   ← UserSetting#theme 추가
└ 언어

GroupedListCard "도구"
├ 용돈 관리
├ API 키
└ 도움말

GroupedListCard "위험한 작업"   ← RiskNotice 톤
├ 워크스페이스 떠나기
└ 워크스페이스 삭제
```

**현재 → To-Be 매핑**:
- 현재 우상단 사용자 메뉴(workspaces, settings, sign out) → 더보기 탭으로 이동
- `user_settings` → "내 계정" 카드
- `workspace_invitations`, `workspace_memberships` → "이 워크스페이스" 카드 안
- 모바일에서 워크스페이스 스위처: `ContextHeader` 우측에 노출 (모든 화면)

---

## 4. 컴포넌트 마이그레이션 매핑

`synthesis.md 6장`의 컴포넌트 사전을 현재 코드에 맞춰 매핑.

### 4.1 신설 partial

| 새 partial | 위치 | 대체하는 것 |
|---|---|---|
| `shared/_screen_shell.html.erb` | layout | `application.html.erb`의 body 골조 |
| `shared/_context_header.html.erb` | layout | 각 페이지의 `<h1>` + `<p>` |
| `shared/_hero_stat.html.erb` | layout | `dashboards/monthly` hero block |
| `shared/_month_nav.html.erb` | shared | `dashboards/monthly` month navigation |
| `shared/_segmented_tabs.html.erb` | shared | `dashboards/_tabs` 일반화 |
| `shared/_chip_scroller.html.erb` | shared | (없음 — 신설) |
| `shared/_filter_sheet.html.erb` | shared | `transactions/index` 인라인 필터 |
| `shared/_bottom_sheet.html.erb` | shared | (없음 — 신설) |
| `shared/_sticky_action_bar.html.erb` | shared | `reviews/show` 하단 액션 묶음 |
| `shared/_empty_state.html.erb` | shared | 각 페이지 인라인 빈 상태 |
| `shared/_inline_alert.html.erb` | shared | `parsing_sessions/index` AI 동의 안내 |
| `shared/_risk_notice.html.erb` | shared | (없음 — 신설) |
| `shared/_ai_badge_card.html.erb` | shared | (없음 — 신설) |
| `shared/_variance_card.html.erb` | dashboards | (없음 — 신설) |
| `shared/_review_inbox_card.html.erb` | dashboards | (없음 — 신설) |
| `shared/_workspace_switcher.html.erb` | layouts | `_navbar`의 워크스페이스 select |
| `shared/_category_source_chip.html.erb` | shared | `transactions/_transaction_row`의 카테고리 표시 |
| `shared/_source_icon.html.erb` | shared | (없음 — 신설; `source_type` 시각화) |
| `shared/_pending_badge.html.erb` | shared | (없음 — 신설) |
| `shared/_amount.html.erb` | shared | 모든 금액 표기 표준화 (`tabular-nums` + 색) |

### 4.2 통합 (중복 제거)

| 현재 | To-Be |
|---|---|
| `transactions/_transaction_row` + `reviews/_transaction_row` | 단일 `transactions/_transaction_row` (상태별 conditional) |
| `transactions/_duplicate_modal` + `reviews/_duplicate_card` + `_duplicate_section` | 단일 `duplicate_confirmations/_row` + `_modal` |

### 4.3 재활용 (변경 없음)

- `categories/_slideover_form`
- `category_mappings/_slideover_form`
- `comments/*`
- `transactions/_form` (스타일만 토큰화)

### 4.4 폐기/이동

| 현재 | 처리 |
|---|---|
| `layouts/_navbar` | 데스크탑 사이드바로 재설계 또는 ContextHeader로 흡수 |
| `layouts/_mobile_bottom_nav` | 5탭으로 재설계 (현재 4탭) |
| `dashboards/_tabs` | `SegmentedTabs` 일반화로 흡수 |

---

## 5. 토큰·테마 도입

### 5.1 파일 위치

```
app/assets/stylesheets/
├ application.tailwind.css   ← @theme 블록 (synthesis.md 4장 전체)
├ tokens/
│   ├ color.css              (선택: 모듈화)
│   ├ typography.css
│   ├ spacing.css
│   └ motion.css
```

### 5.2 Tailwind 4 적용

- `@theme { ... }` 안에 `synthesis.md 4장` 토큰 전체 정의.
- 컴포넌트는 `bg-surface`, `text-secondary` 같은 *시맨틱 utility*만 사용.
- `bg-indigo-600`, `text-gray-900` 같은 *팔레트 utility*는 점진 제거 (codemod 또는 PR별).

### 5.3 다크 모드 전환

- `application.html.erb`의 `class="bg-gray-50"` → `class="bg-page"` (토큰)
- `<html data-theme="auto|light|dark">` 속성 부여
- `UserSetting#theme` 컬럼 추가 (마이그레이션)
- Stimulus controller `theme_controller.js`로 토글

---

## 6. 단계적 로드맵

각 Phase는 별도 PR로 분리. 본 PR(#150)은 디스커버리·ADR만 다룬다.

### Phase 0 — ADR 채택 (본 PR)
- 본 문서 + synthesis 문서 + ADR-0003~ADR-0008 머지
- PRD에 광고 청정 정책 명시 (ADR-0005)

### Phase 1 — 토큰 & 코어 partial (~1주)
- `app/assets/stylesheets/application.tailwind.css`에 `@theme` 도입
- `shared/_screen_shell`, `_context_header`, `_hero_stat`, `_amount` 신설
- `application.html.erb`을 새 shell로 전환 (`bg-gray-50` 제거)
- 다른 페이지는 아직 옛 스타일 — 시각적 회귀 최소

### Phase 2 — 거래 컴포넌트 통합 (~1주)
- `_transaction_row` 단일화, `_source_icon`, `_category_source_chip`, `_pending_badge` 신설
- `transactions/index`, `reviews/show`에 적용
- 인라인 카테고리 변경 → `CategoryMapping` 학습 제안 `_inline_alert`

### Phase 3 — IA 재구성 (~2주, **최대 영향**)
- 라우트: `GET /workspaces/:id/reviews` 신설 (검토함 인덱스)
- 모바일 하단 탭: 5탭으로 (홈/거래/검토함/카테고리/더보기)
- 데스크탑 사이드바 또는 상단 nav: 5탭 매칭
- `parsing_sessions/index`의 입력 폼 → 검토함의 "+ 새로 가져오기" 시트로 이동
- 워크스페이스 스위처 모바일 노출

### Phase 4 — Hero & Variance (~1주)
- `_hero_stat`, `_variance_card`, `_review_inbox_card` 신설
- 홈 대시보드 재구성
- `RecurringPaymentDetector` 결과 카드화

### Phase 5 — 다크 모드 & a11y (~2주)
- `UserSetting#theme` 마이그레이션 + Stimulus 토글
- 컨트라스트 감사 (전체 페이지)
- 키보드 네비게이션 (특히 검토함 단축키)
- focus ring 통일

### Phase 6 — 카피·i18n (~1주)
- `config/locales/ko.yml`에 `synthesis.md 8장` 키 전체 추가
- 모든 view의 한글 하드코딩 → i18n 치환 (검색·치환 codemod)

### Phase 7 — 회고·측정 (~1주)
- 메트릭 비교 (검토 완주율, AI 카테고리 수용률 등)
- 사용자 피드백 수집
- 다음 사이클 인풋

각 Phase 종료 시 ADR 후속 또는 supersede 결정. 본 문서는 ROADMAP 디스커버리이므로 stale될 수 있음 — 권위는 ADR.

---

## 7. 마이그레이션 전략

### 7.1 Strangler Fig (권장)

- 새 partial을 만들 때 기존 partial을 즉시 폐기하지 않는다.
- 페이지 단위로 점진 전환.
- Phase별 PR이 머지될 때마다 한 페이지씩 새 컴포넌트로 갈아탄다.
- 모든 페이지가 새 컴포넌트를 쓰면 옛 partial 일괄 제거.

### 7.2 Big Bang (비권장)

- 한 PR에 모든 변경. 리뷰 불가능 + 회귀 위험.

### 7.3 결정

**Strangler Fig 채택**. ADR-0003에 명시.

---

## 8. 결정해야 할 미해결 질문

본 문서가 답하지 않는 질문 — 별도 ADR 또는 디스커버리 필요.

| 질문 | 결정 시점 | 메모 |
|---|---|---|
| ViewComponent 도입할 것인가? (현재 ERB partial) | Phase 2 시작 전 | 디자인 시스템 도입 비용 vs 효용. 본 문서는 partial 표준화만 권고 |
| Pretendard 폰트 자가 호스팅 vs CDN | Phase 1 | Rails asset pipeline |
| Tailwind 4 마이그레이션 (CSS-first config) | Phase 1 | 현재 Tailwind 버전 확인 필요 |
| `UserSetting#theme` 마이그레이션 | Phase 5 | 기존 user_settings 스키마 확인 |
| 5탭 라우트 path 명명 (`/dashboard` → `/`?) | Phase 3 | breaking change 여부 |
| 키보드 단축키 라이브러리 | Phase 2 | Stimulus 자체 구현 vs hotkeys.js |
| 일러스트 시스템 (빈 상태 이모지/일러스트) | Phase 1~2 | 별도 디스커버리 |

---

## 9. 영향 받는 파일 목록 (예상)

### 9.1 신규 생성
```
app/assets/stylesheets/application.tailwind.css       (또는 동등 진입점)
app/views/shared/_screen_shell.html.erb
app/views/shared/_context_header.html.erb
app/views/shared/_hero_stat.html.erb
app/views/shared/_month_nav.html.erb
app/views/shared/_segmented_tabs.html.erb
app/views/shared/_chip_scroller.html.erb
app/views/shared/_filter_sheet.html.erb
app/views/shared/_bottom_sheet.html.erb
app/views/shared/_sticky_action_bar.html.erb
app/views/shared/_empty_state.html.erb
app/views/shared/_inline_alert.html.erb
app/views/shared/_risk_notice.html.erb
app/views/shared/_ai_badge_card.html.erb
app/views/shared/_workspace_switcher.html.erb
app/views/shared/_category_source_chip.html.erb
app/views/shared/_source_icon.html.erb
app/views/shared/_pending_badge.html.erb
app/views/shared/_amount.html.erb
app/views/dashboards/_variance_card.html.erb
app/views/dashboards/_review_inbox_card.html.erb
app/controllers/reviews_controller.rb                 (인덱스 액션 추가)
app/views/reviews/index.html.erb                      (신규)
config/locales/ko.yml                                 (확장)
db/migrate/YYYYMMDD_add_theme_to_user_settings.rb     (Phase 5)
```

### 9.2 수정
```
app/views/layouts/application.html.erb
app/views/layouts/_navbar.html.erb
app/views/layouts/_mobile_bottom_nav.html.erb
app/views/dashboards/monthly.html.erb
app/views/transactions/index.html.erb
app/views/transactions/_transaction_row.html.erb
app/views/parsing_sessions/index.html.erb
app/views/reviews/show.html.erb
config/routes.rb                                      (reviews 인덱스)
```

### 9.3 폐기
```
app/views/dashboards/_tabs.html.erb                   (SegmentedTabs로 일반화)
app/views/reviews/_transaction_row.html.erb           (transactions/_transaction_row로 통합)
```

---

## 10. 위험 & 완화

| 위험 | 영향 | 완화 |
|---|---|---|
| Phase 3 IA 변경으로 사용자 혼란 | 高 | 자동 redirect, 이전 path 한동안 유지, 안내 토스트 |
| 컴포넌트 통합 시 회귀 | 中 | 각 partial에 visual test (Phase 2부터 testing 강화) |
| 다크 모드 도입으로 컨트라스트 회귀 | 中 | Phase 5에 a11y 감사 게이트 |
| 카피 변경으로 ko.yml 누락 | 低 | Rails `I18n::JustifyTranslations` 또는 lint |
| Tailwind 4 마이그레이션 호환성 | 中 | Phase 1 전 별도 디스커버리·검증 |
| 사용자별 테마 설정 마이그레이션 | 低 | default `auto`, 점진 도입 |

---

## 11. 메트릭 (성공 기준)

`synthesis.md 11장`의 4-layer 중 **Experiment & Operation Layer**가 deferred이므로, 우선 **전후 비교** 메트릭만:

| 메트릭 | 측정 방식 | 기대 |
|---|---|---|
| 검토함 진입 → commit 완주율 | route hits | 상승 |
| 직접 입력 → 저장 시간 | client timer | 감소 |
| AI 카테고리 추천 채택률 | gemini 추천 vs 최종 카테고리 | 상승 |
| 중복 결정 평균 시간 | `DuplicateConfirmationsController` 응답 | 감소 |
| 다크 모드 사용률 | `UserSetting#theme` 비율 | 측정 시작 |
| 모바일 5탭 진입 분포 | route 로그 | 검토함이 2~3순위 |

베이스라인 측정은 Phase 1 시작 직전.

---

## 12. 후속 액션

- [ ] 본 PR(#150) 머지 후 Phase 1 PR 분기 (`claude/ui-redesign-phase-1` 등)
- [ ] Tailwind 4 마이그레이션 사전 디스커버리 (별도 노트)
- [ ] 일러스트 시스템 디스커버리 (별도 노트)
- [ ] PRD에 광고 청정 정책 명시 (ADR-0005 후속)
- [ ] `docs/code-map.md` 갱신 — 새 shared partial 추가 시

---

## 참고

- `docs/discovery/2026-05-15-design-system-synthesis.md` — 본 계획의 원리·토큰·컴포넌트 사전
- `docs/discovery/2026-05-15-toss-ui-analysis.md` — 토스 분석 (P0~P15)
- `docs/discovery/2026-05-15-banksalad-ui-deconstruction.md` — 뱅샐 분석 (P1~P10, BPL)
- `docs/decisions/ADR-0003` ~ `ADR-0008` — 본 PR에서 동시 작성된 결정들
- xef-scale 현재 상태: `docs/context/current-state.md`, `app/views/`
- 본 문서는 디스커버리이며 stale될 수 있다. 권위는 ADR.
