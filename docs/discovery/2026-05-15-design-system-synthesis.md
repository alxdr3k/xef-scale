# 토스 + 뱅크샐러드 종합 보고 — xef-scale 디자인 시스템

- 일자: 2026-05-15
- 입력:
  - `docs/discovery/2026-05-15-toss-ui-analysis.md` (토스 UI 해체분석 + GPT 병행 + 외부 자료 교차검증)
  - `docs/discovery/2026-05-15-banksalad-ui-deconstruction.md` (뱅크샐러드 UI 해체분석 + 외부 자료 + GPT 병행)
- 산출물: 본 문서 = 두 분석을 통합한 **xef-scale 디자인 시스템 결정 권고**. 디스커버리이며 권위가 아니다. 채택 항목은 `docs/decisions/`의 ADR로 승격된다.

---

## 1. 왜 이 문서가 필요한가

xef-scale은 현재 UI가 부족하다. 정확히 어디가 부족한지:

1. **검토 워크플로우**(`pending_review → committed`)가 IA에 잘 안 보인다. 모바일 하단 탭에 "가져오기"가 있고 검토는 그 안에 묻혀 있어, 사용자가 검토할 거래가 쌓여 있어도 진입로가 약하다.
2. **모바일/데스크탑 IA 불일치** — 데스크탑은 5개 메뉴(대시보드/거래/가져오기/용돈 + 알림/스위처), 모바일 하단 탭은 4개(대시보드/결제/가져오기/설정).
3. **컬러 의미축 미분리** — `text-indigo-600`이 CTA, 활성 탭, 링크에 모두 쓰여 "지금 누를 것"이 명확하지 않다.
4. **금융 도메인 어휘 부정확** — "결제 내역", "가져오기" 같은 현재 라벨은 가계부 컨텍스트와 어울리지 않는다.
5. **다크 모드 미지원** — `body class="bg-gray-50"`이 하드코딩되어 있다.
6. **컴포넌트 거버넌스 없음** — 같은 `_transaction_row`가 `reviews/`와 `transactions/`에 따로 있다.

토스 분석과 뱅샐 분석은 각자 풍부하지만 **xef-scale에 무엇을 적용할지**를 직접 명시하지 않는다. 본 문서가 그 다리다.

---

## 2. 두 분석에서 가져갈 결론과 버릴 결론

### 2.1 토스 분석에서 (PR #150 / `2026-05-15-toss-ui-analysis.md`)

| 원칙 | xef-scale 채택 | 이유 |
|---|---|---|
| P0 한 화면 한 기능 | ✅✅ | 검토·기록·분류·회고가 각자 분리되어야 함 |
| P1 숫자가 주인공 | ✅ | hero를 잔액→이번 달 합계·페이스로 번역 |
| P2 라이브 컨텍스트 디폴트 | ✅ | 헤더 인라인을 시장 지수→검토 대기 N건/이번달 vs 지난달 델타로 |
| P3 개인화는 골조 | ◯ 부분 | 워크스페이스명·역할은 노출, 멤버 이름은 신중히 (공유 환경) |
| P4 Dark-first | ❌ | **xef-scale은 light-first**, 다크 동등 지원 — 웹·태블릿 작업 비중 ↑ |
| P5 하나의 액션 컬러 | ◯ 보정 | 토스는 액션 블루로 다 떠받치지만 xef-scale은 **CTA/긍정/주의를 분리** (광고 없으므로 색 분리 여유 있음) |
| P6 AI 별도 채널 | ✅✅ | Gemini 결과는 명확히 출처 표시 |
| P7 광고 라벨링 정직 | n/a | 광고 없음 — P3-banksalad와 동일하게 청정 유지 |
| P8 인라인 액션 | ✅ | TransactionRow 안에서 카테고리·중복·용돈 즉시 토글 |
| P9 빈 상태는 기능 | ✅ | empty state에 워크스페이스명 + 1 CTA |
| P10 그룹핑 | ✅ | 설정·카테고리·매핑은 그룹 카드 |
| P11 스크롤이 상단을 변환 | ◯ | 거래 목록 스크롤 시 헤더가 보고 있는 날짜 그룹 합계로 |
| P12 한국 금융 관행 | ✅ | 원 후치, 천단위 콤마, 소수 없음, "님" 호칭 |
| P13 라이팅도 시스템 | ✅✅ | 마이크로카피를 `ko.yml` 키 사전으로 |
| P14 토큰 자동화 | ✅ | Tailwind `@theme` + CSS 변수 |
| P15 컴포넌트 거버넌스 | ✅ | PR description에 "왜 기존으로 못 푸는가" 1줄 의무 |
| GPT One Thing | ✅ | P0 동의 |
| GPT Value First | ✅ | 인증/입력 부담 전에 "이걸로 무엇이 보이는지" |
| GPT Easy to Answer | ✅ | 카테고리 모달은 2~4개 후보 + AI 추천 1개 |
| GPT Clear Action | ✅✅ | CTA는 "Transaction#create" 같은 기능명 절대 금지, "기록하기/반영하기" |
| GPT Context Based | ✅ | 검토 → 중복 해결 → commit → 카테고리 학습 결과 confirm 자연 흐름 |
| GPT 윤리 보강 (의도적 마찰) | ✅✅ | commit·일괄 삭제·워크스페이스 탈퇴는 일부러 무겁게 |

### 2.2 뱅샐 분석에서 (PR #152 / `2026-05-15-banksalad-ui-deconstruction.md`)

| 원칙 | xef-scale 채택 | 이유 |
|---|---|---|
| P1 다크 + 단일 강조색 | ❌ | 라이트 우선, 의미축 분리 (위 P5 보정과 동일) |
| P2 숫자가 주연 | ✅ | 토스 P1과 동일 |
| P3 가계부 본면 광고 청정 | ✅✅ | 광고 없음이 정체성 |
| P4 친근한 코치 보이스 + 시점 비교 + 진행형 | ◯ | **시점 비교는 ✅** ("지난달 같은 시점 대비"), **진행형/마스코트는 ❌** (트레이드드레스 회피) |
| P5 자동 분류 → 인간 보정 게이미피케이션 | ❌ | "X% 완성" 같은 점수화 회피 — 검토는 *작업*이지 게임이 아님 |
| P6 빈 카드 금지 (CTA로 채움) | ✅ | empty state 패턴 |
| P7 drill-down 다중 시트 | ✅ | 필터·카테고리 선택 |
| P8 예측 수치엔 근거 캡션 | ✅✅ | AI 추천 카테고리, 변동 카드, 예상 마감 지출 모두 근거 같이 |
| P9 직교 차원은 평탄 탭/세그먼트 | ✅ | 검토함의 [파싱 결과 \| 중복] 탭 |
| P10 의미축의 광고 재활용 (dark pattern) | ❌ 강하게 | 광고 없음으로 그냥 부재 |
| GPT 추가 1 `RawTransaction` vs `LedgerEntry` 분리 | ❌ 이미 표현됨 | xef-scale은 `pending_review` ↔ `committed` 머신이 이미 같은 역할 |
| GPT 추가 2 4-layer 시스템 | ✅ 부분 | Product Language + Data Transformation + Insight & Coaching 채택, Experiment Layer는 deferred |
| GPT 추가 3 변동 정보 중심 | ✅✅ | 대시보드 1번 카드를 **변동 카드**로 |
| BPL 컴포넌트 문법 (Scene/Section/Card/Row/Chip) | ✅ | xef-scale Product Language 명명에 채택 |

### 2.3 두 분석의 공통 결론 (강한 신호)

두 분석이 독립적으로 같은 결론에 수렴한 항목 — 가장 신뢰할 수 있는 베이스라인:

1. **숫자가 주인공이다** (토스 P1 / 뱅샐 P2).
2. **한 화면 한 행동/메시지** (토스 P0 / 토스 GPT One Thing / 뱅샐 9.15-1).
3. **AI/예측 결과는 시각적·언어적으로 격리** (토스 P6 / 뱅샐 P8).
4. **빈 상태는 다음 행동의 입구** (토스 P9 / 뱅샐 P6).
5. **카드/그룹으로 정보 묶기** (토스 P10 / 뱅샐 전체).
6. **광고를 가계부 본면에 두지 않는다** (토스 P7 / 뱅샐 P3).
7. **카피는 디자인 시스템의 일부** (토스 P13 / 뱅샐 9.16.9 "금융 용어 → 생활 언어").
8. **컴포넌트는 거버넌스로 관리** (토스 P15 / 뱅샐 BPL).

이 8개는 **xef-scale에서 협상 대상이 아닌 베이스라인**.

### 2.4 두 분석이 갈라지는 결론

| 축 | 토스 | 뱅샐 | xef-scale 결정 |
|---|---|---|---|
| 라이트/다크 | dark-first | dark-first | **light-first**, 다크 동등 지원 (작업 도구이므로) |
| 단일 강조색 vs 분리 | 단일 (블루) | 단일 (민트) | **분리** (action/positive/warning) — 광고 없음이 자유도를 줌 |
| 게이미피케이션 | 없음 (보수적) | 강함 ("90% 완성") | **없음** — 검토는 작업, 점수화 회피 |
| 마스코트/일러스트 | 3D 스티커 | 돼지 | **없음** — 트레이드드레스 회피 + 도구 정체성 |
| 시점 비교 카피 | 라이브 컨텍스트 | 진행형 코치 | **시점 비교만** ("지난달 같은 시점 대비" OK, "덜 쓰는 중" 표현 회피) |
| 슈퍼앱 nav | 5탭 | 5탭 (가계부 중앙) | **5탭** but 검토함 별도 (아래 5장) |

---

## 3. 최종 xef-scale 디자인 원칙 (압축 12)

본 문서에서 추출한 **xef-scale 채택 원칙 12개**. 토스 P0~P15 + GPT 12원칙 + 뱅샐 P1~P10 + 윤리 보강을 통합·압축.

| # | 원칙 | 한 줄 | 출처 매핑 |
|---|---|---|---|
| **X1** | 숫자가 주인공 | 잔액·이번달 합계·페이스·예상 마감을 화면 최대 글자로 | 토스 P1 / 뱅샐 P2 |
| **X2** | 한 화면 한 과업 | 입력 / 검토 / 분류 / 회고 / 공유 중 *하나만* | 토스 P0 / GPT One Thing |
| **X3** | 라이브 컨텍스트 | 헤더 인라인에 "이번 달 vs 지난달 ±%" 또는 "검토 대기 N건" | 토스 P2 / 뱅샐 9.16.5 변동 정보 |
| **X4** | AI 별도 채널 | Gemini 결과는 보라 + ✨ + 출처 표시, 절대 액션 블루로 표시 안 함 | 토스 P6 / 뱅샐 P8 |
| **X5** | 의미축 분리 | CTA / 긍정(수입) / 주의(pending) / 위험(error) 색을 모두 분리 | 뱅샐 P1 보정 |
| **X6** | 광고 청정 | 본면에 외부 금융상품 0건. 채택 시 별도 라벨 + 의미축 보호 | 토스 P7 / 뱅샐 P3 |
| **X7** | 빈 상태 = 다음 행동 입구 | 이모지/일러스트 + 워크스페이스명 호명 + 1 CTA | 토스 P9 / 뱅샐 P6 |
| **X8** | 인라인 액션 | TransactionRow에서 카테고리·용돈·중복 즉시 토글, 모달 회피 | 토스 P8 |
| **X9** | 그룹 카드 | 설정·카테고리·매핑·멤버는 카드 그룹, 행 단위 chevron | 토스 P10 / 뱅샐 P7 |
| **X10** | 마이크로카피는 시스템 | `ko.yml`을 단일 출처로. 카피 하드코딩 금지 | 토스 P13 / 뱅샐 9.16.9 |
| **X11** | 의도적 마찰 | commit / 일괄 삭제 / 워크스페이스 탈퇴는 일부러 무겁게 (확인 + 영향 범위 + 비가역 명시) | 토스 GPT 윤리 보강 |
| **X12** | 컴포넌트 거버넌스 | PR에 "왜 기존 카탈로그로 못 푸는가" 1줄 의무. Scene/Section/Card/Row/Chip 명명 통일 | 토스 P15 / 뱅샐 BPL |

이 12개가 **xef-scale 디자인 시스템의 헌법**. 다른 모든 세부 결정은 X1~X12에서 파생되어야 한다.

---

## 4. 디자인 토큰 (단일 진실 원천)

토스 분석 11.2와 뱅샐 분석 10.3을 통합·정정. **Tailwind CSS 4의 `@theme` + CSS `light-dark()` 로 정의**한다.

### 4.1 컬러 — 시맨틱 우선

```css
@theme {
  /* === Surface === */
  --color-bg-page:        light-dark(#fafafa, #0f1014);
  --color-bg-surface:     light-dark(#ffffff, #181a1f);
  --color-bg-elev:        light-dark(#f4f4f5, #21242b);
  --color-bg-sunken:      light-dark(#f4f4f5, #0a0b0e);
  --color-bg-overlay:     light-dark(rgba(0,0,0,0.5), rgba(0,0,0,0.6));

  /* === Border === */
  --color-border-subtle:  light-dark(#e5e5e5, #2a2d33);
  --color-border-strong:  light-dark(#d4d4d4, #3f434b);
  --color-border-focus:   light-dark(#4f46e5, #818cf8);  /* a11y outline */

  /* === Text === */
  --color-text-primary:   light-dark(#0a0a0a, #fafafa);
  --color-text-secondary: light-dark(#525252, #a3a3a3);
  --color-text-tertiary:  light-dark(#737373, #6b7280);
  --color-text-disabled:  light-dark(#a3a3a3, #525252);
  --color-text-inverse:   light-dark(#ffffff, #0a0a0a);

  /* === Semantic action — 각 토큰은 단 하나의 의미만 === */
  --color-action:         light-dark(#4f46e5, #818cf8);  /* CTA 전용 */
  --color-action-hover:   light-dark(#4338ca, #6366f1);
  --color-action-on:      #ffffff;
  --color-action-subtle:  light-dark(#eef2ff, #312e81);  /* CTA 배경 */

  --color-positive:       light-dark(#15803d, #4ade80);  /* 수입·환급 — CTA와 분리 */
  --color-positive-subtle: light-dark(#dcfce7, #14532d);

  --color-warning:        light-dark(#b45309, #f59e0b);  /* pending_review */
  --color-warning-subtle: light-dark(#fef3c7, #451a03);

  --color-info:           light-dark(#0369a1, #38bdf8);  /* duplicate · AI 보조 */
  --color-info-subtle:    light-dark(#e0f2fe, #082f49);

  --color-danger:         light-dark(#b91c1c, #f87171);  /* error · 비가역 액션 */
  --color-danger-subtle:  light-dark(#fee2e2, #450a0a);

  --color-neutral-expense: var(--color-text-primary);    /* 지출은 강조색 사용 안 함 */

  /* === AI 채널 — 보라로 격리 === */
  --color-ai:             light-dark(#7c3aed, #a78bfa);
  --color-ai-subtle:      light-dark(#f5f3ff, #1e1b2e);
  --color-ai-border:      light-dark(#ddd6fe, #5b21b6);

  /* === Category palette (chart/chip) — 호 회전 === */
  --color-category-1:  light-dark(#0891b2, #67e8f9);
  --color-category-2:  light-dark(#0d9488, #5eead4);
  --color-category-3:  light-dark(#65a30d, #bef264);
  --color-category-4:  light-dark(#ca8a04, #fde047);
  --color-category-5:  light-dark(#ea580c, #fdba74);
  --color-category-6:  light-dark(#db2777, #f9a8d4);
  --color-category-7:  light-dark(#9333ea, #d8b4fe);
  --color-category-8:  light-dark(#4f46e5, #a5b4fc);  /* action과 톤 분리 위해 채도 낮춤 */
  --color-category-9:  light-dark(#475569, #94a3b8);
  --color-category-10: light-dark(#78716c, #a8a29e);
}
```

**X5 보장**: `--color-action` / `--color-positive` / `--color-warning` / `--color-info` / `--color-danger`가 절대 같은 톤이 되지 않도록 분리. CTA(인디고)와 수입(그린)이 헷갈리지 않게.

**다크 모드 토큰**: 모두 `light-dark()`로 자동 페어. 사용자 토글(`UserSetting#theme: auto|light|dark`)로 전환.

### 4.2 타이포

```css
@theme {
  --font-sans: "Pretendard Variable", "Pretendard", system-ui, -apple-system, sans-serif;
  --font-mono: ui-monospace, "SF Mono", monospace;

  /* Variant: tabular-nums 강제 — 모든 금액 표기에 적용 */
  --text-display: 2.5rem;   /* hero 숫자 — 이번 달 합계 */
  --text-title:   1.5rem;   /* 페이지 타이틀 */
  --text-section: 1.125rem; /* 섹션 헤딩 */
  --text-amount:  1rem;     /* 거래 row 금액 */
  --text-body:    0.9375rem;
  --text-meta:    0.8125rem;
  --text-caption: 0.75rem;
}
```

규칙:
- 모든 금액은 `font-variant-numeric: tabular-nums` 강제 — row scroll 시 자릿수 흔들림 방지.
- 금액에는 천단위 콤마 + "원" 후치. 부호(-/+)는 숫자 앞 (한국 관행).
- hero는 화면당 *하나*만.

### 4.3 간격·라운드·그림자

```css
@theme {
  --space-1: 0.25rem;
  --space-2: 0.5rem;
  --space-3: 0.75rem;
  --space-4: 1rem;
  --space-5: 1.5rem;
  --space-6: 2rem;
  --space-7: 3rem;

  --radius-xs:   4px;   /* input */
  --radius-sm:   8px;   /* button, chip */
  --radius-md:   12px;  /* card */
  --radius-lg:   20px;  /* modal, sheet */
  --radius-full: 9999px;

  --shadow-card:  0 1px 2px rgba(0,0,0,0.04);
  --shadow-elev:  0 4px 16px rgba(0,0,0,0.08);
  --shadow-sheet: 0 -2px 24px rgba(0,0,0,0.12);
}
```

- 리스트 행 높이 최소 48px (`space-7`) — 모바일 터치 타깃.
- 라운드는 토스의 매우 큰 곡률(24px+ pill 탭바)을 따라가지 않는다. 시각 모방 회피.

### 4.4 모션

```css
@theme {
  --duration-instant: 100ms;
  --duration-fast:    150ms;
  --duration-base:    220ms;
  --duration-slow:    400ms;
  --ease-standard:    cubic-bezier(0.2, 0, 0, 1);
  --ease-emphasized:  cubic-bezier(0.3, 0, 0.1, 1);
}
```

금융 데이터는 즉시 피드백 우선. 화려한 트랜지션 회피.

---

## 5. 정보 구조 — xef-scale 5탭

현재 IA의 문제(검토함 진입로 약함, 모바일/데스크탑 불일치)를 해결.

```
┌─ 데스크탑 상단 nav / 모바일 하단 bottom-tabs ─┐
│
│  1. 홈           — 변동 카드 · 검토 대기 · 카테고리 breakdown · 반복 결제
│  2. 거래         — 목록 / 캘린더 듀얼 뷰 · 필터 · 검색 · 추가
│  3. 검토함 ★    — 파싱 결과 N · 중복 후보 N (현재는 가져오기에 묻혀 있음)
│  4. 카테고리     — 카테고리 · 학습된 매핑
│  5. 더보기       — 워크스페이스 · 멤버 · 알림 · 설정 · 용돈 · 도움말
│
│  ※ "용돈"은 거래 인라인 토글로 노출하고, 더보기 안에 관리 진입로
└──────────────────────────────────────────────┘
```

핵심 결정:
- **검토함을 독립 탭으로 승격** (현재 `parsing_sessions/index`에 묻혀 있음). xef-scale의 본질은 검토 워크플로우이므로 IA의 1순위.
- **"가져오기"라는 탭 이름은 폐기**. 검토함 안에 "+ 새로 가져오기" 액션으로 흡수.
- **데스크탑/모바일 IA 단일화** — 5탭 동일. 데스크탑은 사이드바, 모바일은 하단 탭바.
- **워크스페이스 스위처를 모바일 헤더에도** 노출 (현재 데스크탑 전용).

---

## 6. 컴포넌트 사전 (Product Language)

뱅샐 BPL(컴포넌트=단어, 화면=문장)을 채택하되 어휘는 xef-scale 도메인.

### 6.1 명명 규칙

| 레이어 | 예시 |
|---|---|
| **Scene** (route) | `ReviewInboxScene`, `TransactionListScene`, `DashboardScene` |
| **Section** | `MonthSummarySection`, `VarianceSection` |
| **Card** | `VarianceCard`, `ReviewInboxCard`, `RecurringPaymentCard` |
| **Row** | `TransactionRow`, `DuplicateConfirmationRow`, `CategoryMappingRow` |
| **Chip / Badge** | `CategorySourceChip`, `PendingBadge`, `RoleBadge` |
| **Sheet / Modal** | `FilterSheet`, `CategoryPickerSheet`, `DuplicateResolveModal` |

ERB 파셜 경로:
- `app/views/shared/_<component>.html.erb` (공통)
- `app/views/<resource>/_<component>.html.erb` (도메인 특화)
- 향후 ViewComponent 도입은 별도 ADR (현재는 ERB partial 표준화 단계).

### 6.2 도메인 컴포넌트 (xef-scale 고유)

| 컴포넌트 | 역할 | 상태/슬롯 |
|---|---|---|
| `WorkspaceSwitcher` | 현재 워크스페이스 + 역할 표시 + 전환 | role: owner/co_owner/member_write/member_read |
| `MoneySummary` | 월 hero (지출/수입) | role에 따라 일부 마스킹 가능 |
| `VarianceCard` | "지난달 같은 시점 대비" + 예상 마감 | improving / worsening / neutral |
| `ReviewInboxCard` | 검토 대기 진입 카드 (홈 노출용) | count, last_updated |
| `TransactionRow` | 거래 1행 — 인라인 액션 포함 | committed / pending_review / discarded |
| `TransactionRow.SourceIcon` | 입력 경로 (✍ 수기 / 💬 SMS / 📷 이미지 / 🔗 API) | source_type 5종 |
| `TransactionRow.CategorySourceChip` | 카테고리 + 출처 표시 (mapping/keyword/gemini/manual) | 4단계 폴백 시각화 |
| `DateGroupHeader` | 날짜 헤더 + 그날 합계 | sticky 옵션 (스크롤 시 그룹 합계 노출) |
| `ParsingSessionCard` | 검토함의 세션 묶음 | processing / ready / committed / rolled_back |
| `DuplicateConfirmationRow` | 중복 후보 2건 비교 + 3-way 결정 | pending / keep_both / keep_original / keep_new |
| `CategoryMappingRow` | 매핑 규칙 1행 | priority 1~4 (mapping/keyword/gemini/manual) |
| `AIBadgeCard` | Gemini 출력 묶음 (보라 outline + ✨) | confidence: high/med/low |
| `RiskNotice` | 의도적 마찰 — 비가역 액션 직전 | warning/danger 톤 |
| `RoleBadge` | 멤버 역할 표시 | 4종 |

### 6.3 일반 컴포넌트

| 컴포넌트 | 역할 |
|---|---|
| `ScreenShell` | safe area + 헤더 + 메인 + 바텀바 슬롯 |
| `ContextHeader` | 화면명 + 라이브 컨텍스트 + 우측 액션 아이콘 (최대 3개) |
| `HeroStat` | 화면 최상위 큰 숫자 + 보조 델타 + 1 CTA |
| `MonthNav` | `< 5월 >` 컨트롤 |
| `SegmentedTabs` | 모드 전환 (목록/캘린더, 파싱/중복) |
| `ChipScroller` | 필터 가로 스크롤 |
| `BottomSheet` | 모바일 시트 + 풀폭 CTA 슬롯 |
| `Modal` | 데스크탑 모달 |
| `StickyActionBar` | 하단 고정 듀얼 CTA |
| `EmptyState` | 이모지 + 워크스페이스명 호명 + 1 CTA |
| `FilterRow` | 좌 라벨 / 우 값 + chevron (시트 진입) |
| `SwitchRow` | 좌 라벨 / 우 토글 (즉시 반영) |
| `SettingsRow` | 좌 아이콘+라벨 / 우 값+chevron |
| `Toast` | 비차단 자동 사라짐 알림 |
| `InlineAlert` | 인라인 경고 (action/warning/info/danger) |

---

## 7. 페이지 패턴 (5탭 골조)

### 7.1 홈 (`/dashboard`)

```
ContextHeader  ("이번 달 지출" + 라이브: 지난달 대비 ±%)
├ MonthNav  + WorkspaceSwitcher (모바일은 헤더 안)
├ HeroStat  (이번 달 합계 + 보조: 예산 잔여 / CTA "예산 조정")
│
├ VarianceCard  ("지난달 같은 시점 대비 -12.4% · 예상 마감 약 2,840,000원")
│   └ [상세 보기]
│
├ ReviewInboxCard  ("검토 대기 N건 · 중복 N건") — N > 0일 때만 노출
│   └ CTA "지금 검토"
│
├ Section "카테고리별"
│   └ Row × N: CategorySourceChip · 합계 · 막대 · chevron
│
├ Section "반복 결제" (RecurringPaymentDetector 결과)
│   └ Row × N: 결제명 · 다음 결제 예상일 · 금액
│
└ BottomNav
```

대표 행동: **이번 달 페이스 파악 + 검토 대기 처리 + 카테고리 드릴다운**.

### 7.2 거래 (`/workspaces/:id/transactions`)

```
ContextHeader  ("거래" + 라이브: 보고 있는 기간 합계)
├ SegmentedTabs  [목록 | 캘린더]
├ ChipScroller  (카테고리 / 금융기관 / 상태 / 결제수단)
├ Toolbar  [🔍 검색] [+ 추가]
│
├ (목록) DateGroupHeader × N  → TransactionRow × N
│        ↑ 스크롤 시 헤더 sticky + 보고 있는 날짜 그룹 합계로 변환
│
├ (캘린더) CalendarGrid (셀별 +/- 합계, 무지출일 시각화)
│
└ + Floating "+" (추가 시트 진입)
```

### 7.3 검토함 (`/workspaces/:id/reviews` — 신설)

```
ContextHeader  ("검토" + 라이브: "거래 N건 · 중복 M건")
├ SegmentedTabs  [파싱 결과 N | 중복 후보 M]
│
├ (파싱 결과 탭)
│   ParsingSessionCard × N (이미지·텍스트 원본 미리보기 포함)
│   ├ TransactionRow × N (각 행 인라인 편집 가능)
│   └ [원본 보기]
│
├ (중복 후보 탭)
│   DuplicateConfirmationRow × N (좌우 비교 + 3-way 선택)
│
├ RiskNotice  (미해결 중복이 있을 때: "중복 N건을 먼저 정리해야 반영할 수 있어요")
│
└ StickyActionBar
    ├ secondary "취소"
    └ primary  "거래 내역 반영 (N건)"   ← 미해결 중복 있으면 비활성 + 사유 명시
```

키보드 단축키 (데스크탑):
- `j/k` 행 이동
- `c` 카테고리 변경 sheet
- `d` 폐기
- `x` 중복으로 표시
- `enter` 다음 거래
- `cmd/ctrl + enter` 전체 반영

### 7.4 카테고리 (`/workspaces/:id/categories`)

```
ContextHeader  ("카테고리" + 라이브: "N개 · 학습된 매핑 M건")
├ Section "내 카테고리"
│   CategoryRow × N
│
├ Section "학습된 매핑" (CategoryMapping)
│   CategoryMappingRow × N — 가맹점 → 카테고리 + source badge + 마지막 적용일
│
└ AIBadgeCard "AI가 추천하는 새 카테고리" (Gemini 후보 — 신뢰도 표시)
```

### 7.5 더보기 (`/workspaces/:id/more`)

```
ProfileRow  (워크스페이스명 + 역할 chip)
├ GroupedListCard "이 워크스페이스"
│   ├ 멤버 · N명
│   ├ 초대 링크
│   └ 예산
├ GroupedListCard "AI 설정"
│   ├ 텍스트 파싱 ✨ toggle
│   ├ 이미지 파싱 ✨ toggle
│   └ 카테고리 추천 ✨ toggle
├ GroupedListCard "내 계정"
│   ├ 알림
│   ├ 화면 테마 (auto / light / dark)
│   └ 언어
├ GroupedListCard "도구"
│   ├ 용돈 관리
│   ├ API 키
│   └ 도움말
└ GroupedListCard "위험한 작업"  (RiskNotice 톤)
    ├ 워크스페이스 떠나기
    └ 워크스페이스 삭제
```

---

## 8. UX Writing 사전

`config/locales/ko.yml` 단일 출처. 카피 하드코딩 금지.

### 8.1 CTA 키

| 키 | 표현 | 컨텍스트 |
|---|---|---|
| `cta.record` | 기록하기 | 거래 신규 |
| `cta.commit_review` | 거래 내역 반영 | 검토 후 commit |
| `cta.review_now` | 지금 검토 | 홈에서 검토함 진입 |
| `cta.paste_sms` | 문자 붙여넣기 | text paste 시트 |
| `cta.upload_shot` | 스크린샷 올리기 | image upload |
| `cta.add_manual` | 직접 입력하기 | manual 폼 |
| `cta.cancel_review` | 검토 취소 | 검토 화면 |
| `cta.adjust_budget` | 예산 조정 | 홈 hero |

### 8.2 라이브 컨텍스트

| 키 | 표현 |
|---|---|
| `live.month_pace` | "지난달 같은 시점 대비 %{delta}%" |
| `live.expected_end` | "예상 마감 약 %{amount}원" |
| `live.review_pending` | "검토 대기 %{count}건" |
| `live.duplicate_pending` | "중복 후보 %{count}건" |

### 8.3 빈 상태

| 키 | 표현 |
|---|---|
| `empty.no_tx` | "%{workspace}에 아직 기록된 거래가 없어요" |
| `empty.no_review` | "검토할 거래가 없어요. 모두 반영됐어요." |
| `empty.no_category` | "%{workspace}의 첫 카테고리를 만들어 볼까요?" |

### 8.4 AI 라벨링

| 키 | 표현 |
|---|---|
| `ai.suggested` | "AI가 추천했어요" |
| `ai.low_confidence` | "추천이 확실하지 않아요 — 한 번 더 확인해 주세요" |
| `ai.source_gemini` | "Gemini 추천" |

### 8.5 위험 행동 (X11 — 의도적 마찰)

| 키 | 표현 |
|---|---|
| `risk.commit_locked` | "중복 %{count}건을 먼저 정리해야 반영할 수 있어요" |
| `risk.workspace_leave` | "떠나면 %{workspace}의 거래를 더 이상 볼 수 없어요. 다른 멤버에게는 영향이 없어요." |
| `risk.workspace_delete` | "삭제하면 거래 %{count}건이 모두 사라져요. 되돌릴 수 없어요." |
| `risk.bulk_delete` | "거래 %{count}건을 삭제할게요. 되돌릴 수 없어요." |
| `risk.rollback_session` | "이 세션의 거래 %{count}건이 모두 검토 전 상태로 돌아가요." |

### 8.6 학습 알림 (인라인)

| 키 | 표현 |
|---|---|
| `learn.suggest_mapping` | "다음 같은 가맹점부터는 이 카테고리로 자동 분류할까요?" |
| `learn.applied` | "학습됐어요. 같은 가맹점부터는 자동으로 분류돼요." |

### 8.7 보이스 규칙

1. **기능명 금지** — "Transaction 생성" / "Review commit" / "Mapping save" 같은 시스템 어휘를 사용자 향 카피에서 절대 사용 안 함.
2. **존댓말 통일** — 모든 사용자 향 문장은 "-요/-어요" 종결.
3. **워크스페이스 컨텍스트 인지** — 공유 환경이므로 "당신" 대신 "%{workspace}", "이번 달", "이 워크스페이스".
4. **AI 출력은 단정 어조 금지** — "추천했어요", "추측이에요", "확인해 주세요".
5. **위험 행동은 영향 범위 명시** — 거래 N건, 멤버에 미치는 영향, 비가역 여부.
6. **뱅샐 표현 회피** — "덜 쓰는 중", "X% 완성" 같은 진행형/게이미피케이션 어휘는 트레이드드레스 차원에서 금지.

---

## 9. 안전장치 — 의도적 마찰 (X11)

토스의 매끄러움이 가계부에서 항상 옳지 않다 (토스 분석 9.8). xef-scale에서 일부러 마찰을 두는 행동:

| 행동 | 마찰 장치 |
|---|---|
| `Transaction#commit` (검토 → 반영) | 미해결 중복 자동 카운트 → CTA 비활성 + 사유 명시 |
| 거래 일괄 삭제 | RiskNotice + 삭제 건수·합계 표시 |
| `CategoryMapping` 일괄 재적용 (과거 거래 소급) | "거래 N건이 새 카테고리로 바뀌어요" 미리보기 + 확정 |
| 워크스페이스 탈퇴/삭제 | 2단계 확인 + 워크스페이스명 직접 입력 |
| `ParsingSession` rollback | "이 세션의 거래 N건이 검토 전 상태로 돌아가요" 확인 |
| AI 토글 끄기 | "이번 달 N건이 AI 파싱으로 들어왔어요" 안내 |
| AI 동의 (첫 사용) | Value First 카드: "Gemini가 무엇을 하는지" 먼저 보여주고 동의 |
| API 키 생성 | scope 명시 + "이 키로 무엇을 할 수 있는지" 미리보기 |

원칙: **저위험(기록·검토·카테고리 변경)은 매끄럽게, 고위험·비가역은 일부러 무겁게**.

---

## 10. 4-layer 시스템 매핑 (뱅샐 9.16.12)

| Layer | xef-scale 구현 |
|---|---|
| **Product Language** | 본 문서 6장의 컴포넌트 사전 + 도메인 어휘 (`Workspace`, `ParsingSession`, `CategoryMapping`, `DuplicateConfirmation`). ERB 파셜로 코드화. |
| **Data Transformation** | 이미 `pending_review` ↔ `committed` 머신, `DuplicateConfirmation`, 3단계 카테고리화 폴백, `RecurringPaymentDetector`로 구현. UI에서 출처(`source_type`, 카테고리 source) 노출만 추가. |
| **Insight & Coaching** | `VarianceCard`, `RecurringPaymentCard`. 광고 동선 없음. 비난 없는 카피. |
| **Experiment & Operation** | (현재 없음) — 본 사이클에서는 deferred. 도입 시 별도 ADR. 우선은 **전후 비교 메트릭**만 (검토 완주율, AI 카테고리 수용률 등). |

---

## 11. 두 분석을 합쳐서 새로 보이는 것

본 통합 작업에서만 도출된 인사이트:

1. **xef-scale의 핵심 차별점은 "검토 워크플로우"다.** 토스도 뱅샐도 검토를 명시적 머신으로 안 두지만(`pending_review` 같은 게 없음), xef-scale은 3-way 입력 + AI 파싱이 본질이라 검토함이 *진짜 1번 탭*이 되어야 한다. → 5탭 IA에 검토함 별도 승격.

2. **광고가 없다는 게 디자인 자유도를 만든다.** 토스(P5 단일 블루) / 뱅샐(P1 단일 민트)이 모두 *어쩔 수 없이* 단일 강조색에 갇혀 있는 이유는 광고/추천 영역 때문. xef-scale은 광고 청정이므로 CTA / 긍정 / 주의 / 위험 색을 모두 분리할 수 있다 → X5.

3. **워크스페이스 = 공유는 새로운 차원이다.** 토스/뱅샐은 개인 도구. xef-scale은 가족·팀 공유라 "누가 입력/검토/카테고리화했는지"가 화면에 보여야 한다. 단 *개인 거래 내역의 프라이버시* 와 *공유 가시성* 의 균형이 필요 → role-based view (`member_read`는 일부 마스킹).

4. **3-way 입력의 신뢰도 차이를 UI에 노출해야 한다.** `manual`은 즉시 commit, `text_paste`/`image_upload`는 pending_review. SourceIcon으로 일관 표시 → 사용자가 "어디서 들어온 거래인지" 1초에 파악.

5. **뱅샐의 BPL × 토스의 P15 컴포넌트 거버넌스가 한 짝이다.** BPL이 컴포넌트 사전이라면, P15는 사전을 *지키는* 거버넌스. 둘이 같이 있어야 동작.

---

## 12. 후속 액션 (실행 계획)

### 12.1 ADR로 승격할 결정들

본 문서에서 채택을 권고하는 결정 6개를 ADR로 분리:

1. **ADR-0003 — Design system 채택 & Product Language**: X1~X12 + 4장 토큰 + 6장 컴포넌트 사전.
2. **ADR-0004 — Review Inbox 독립 탭 승격**: 5탭 IA의 핵심 변화.
3. **ADR-0005 — 광고 청정 정책 명문화**: PRD에 추가.
4. **ADR-0006 — CTA와 시맨틱 컬러 분리 (X5)**: 단일 인디고 → action/positive/warning/info/danger 분리.
5. **ADR-0007 — 카테고리 출처 시각화**: mapping/keyword/gemini/manual 4단계 폴백 UI 노출.
6. **ADR-0008 — 라이트 우선 + 다크 동등 지원**: `light-dark()` 토큰 + UserSetting#theme.

### 12.2 UI 재구성 작업 계획

`docs/discovery/2026-05-15-ui-redesign-plan.md` 별도 문서로 분리.

### 12.3 본 문서가 다루지 않는 것

- 일러스트 시스템 (트레이드드레스 회피 차원에서 토스/뱅샐 일러스트 톤 모두 비채택). 일러스트 가이드는 별도 디스커버리.
- 실험 인프라(A/B). 트래픽이 충분해진 후 별도 ADR.
- 외화·다중 통화. 현 PRD에 명시 안 됨.
- 접근성 감사 절차. ADR-0003에 a11y 기본만 포함하고 상세는 별도 디스커버리.

---

## 13. 한 줄 결론

> xef-scale의 디자인 시스템은 **"검토 가능한 정직함 + 변동 중심 통찰 + 공유 가능한 워크스페이스"** 를 세 축으로 한다. 토스와 뱅샐에서 가져오는 것은 *시각이 아니라 기율*이며, 둘과 다르게 가져가는 것은 **검토 워크플로우의 1번 탭 승격 · 광고 청정의 색 자유도 활용 · 게이미피케이션 회피** 다.

---

## 참고

- `docs/discovery/2026-05-15-toss-ui-analysis.md` (본 PR #150)
- `docs/discovery/2026-05-15-banksalad-ui-deconstruction.md`
- `docs/discovery/2026-05-15-ui-redesign-plan.md` (본 PR — UI 재구성 실행 계획)
- `docs/decisions/ADR-0003` ~ `ADR-0008` (본 PR — 본 문서에서 승격된 ADR들)
- xef-scale 현재 상태: `docs/context/current-state.md`, `app/views/`
- 본 문서는 디스커버리 노트이며 ADR이 권위의 출처다.
