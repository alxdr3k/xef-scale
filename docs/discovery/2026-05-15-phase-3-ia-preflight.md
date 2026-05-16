# Phase 3 IA Preflight & Deferred Triage

- 일자: 2026-05-15
- 입력:
  - `docs/discovery/2026-05-15-ui-redesign-plan.md §6` (단계적 로드맵, Phase 1~7)
  - `docs/decisions/ADR-0003` ~ `ADR-0010` (디자인 시스템·IA·신뢰 레이어 결정 묶음)
  - main 머지 이력 (#158~#167) — Phase 1·2 완료분
- 산출물: Phase 3 진입 결정 + Phase 2 deferred triage 표 + Phase 3 IA scope + IA 진입 전 검토할 5개 contract 포인트
- 범위: 본 문서는 **디스커버리**이며 권위가 아니다. 채택될 결정은 별도 ADR로 승격한다.

---

## 0. TL;DR

1. **Phase 2 deferred 전체를 먼저 처리하지 않는다.** Phase 3 IA 재구성으로 진입하되, IA에 직접 영향을 주는 deferred만 Phase 3 첫 slice에 흡수한다.
2. **본 PR은 IA preflight slice다.** 구현이 아니라 *Phase 3가 흔들리지 않게 범위·선행조건·계약을 잠그는 것*이 목적.
3. **Phase 3는 두 번째 PR(IA Skeleton)부터 시작**한다. 본 PR(IA Preflight)은 docs 위주, 코드 변경은 IA 진입에 *진짜* 걸림돌인 항목으로만 한정.

권고 결론: `Phase 2 deferred 전체 선처리 금지 → Phase 3 IA preflight (본 PR) → Phase 3 IA skeleton → 화면 단위 PR`.

---

## 1. 진입 판단 (왜 지금 Phase 3로 가는가)

### 1.1 Phase 2 종료 신호

main 기준 머지된 Phase 2 PR (시간 역순):

| PR | 주제 | Phase 2 산출물 매핑 |
|---|---|---|
| #167 | explicit opt-in 학습 제안 (`category_learning_suggestion`) | ADR-0007 §4 |
| #166 | `_inline_alert` AI 동의 안내 채택 | ui-redesign-plan §4.1 |
| #165 | `shared/_inline_alert` 신설 | ui-redesign-plan §4.1 |
| #164 | `_category_source_chip` 채택 (category_cell) | ADR-0007 §1 |
| #163 | `_source_icon` 채택 (source_metadata_cell) | ADR-0007 / Phase 2 partial 정착 |
| #162 | `_pending_badge` 채택 (merchant_cell) | Phase 2 partial 정착 |
| #161 | `transactions/_transaction_row` ↔ `reviews/_transaction_row` 통합 | ui-redesign-plan §4.2 |
| #160 | `_source_icon` / `_pending_badge` / `_category_source_chip` 신설 | ui-redesign-plan §4.1 |
| #159 | core partial + `bg-page` shell | Phase 1 잔여 |
| #158 | `@theme` 토큰 + Pretendard 자가 호스팅 (ADR-0010) | Phase 1 |

Phase 2의 핵심 산출물은 main에 들어갔다. 즉 **현재 병목은 더 이상 "거래 row 컴포넌트 통합"이 아니다.**

### 1.2 진짜 병목은 IA·신뢰 레이어

xef-scale은 이미 핵심 정책이 모두 붙어 있다:

- 카테고리 자동 분류 (3단계 폴백) + explicit opt-in 학습 제안 (ADR-0007 §4)
- 텍스트·이미지 파싱 + `pending_review → committed` 검토 흐름 (PRD)
- 개인정보 purge (`ProcessedFile#blob_purged_at`, ADR-0002)
- AI 동의 (워크스페이스 토글 3종 + `ai_consent_acknowledged_at`)

지금 사용자가 마주하는 문제는 *기능 하나가 부족한 것*이 아니라, **이 기능들이 한 흐름 안에서 일관된 신뢰 모델로 보이지 않는다는 점이다**:

- 검토함은 IA 1번 시민이 아니라 "가져오기" 탭 안에 묻혀 있다 (ADR-0004 §Context).
- 카테고리 결정 메커니즘은 ADR-0007에서 *4값*으로 분리됐지만, 거래 row에 노출되지 않는다 (현재 `_category_cell`은 `decision:`을 전달하지 않음 → chip의 decision 마크는 dormant).
- `CategoryMapping#source`(매핑 출처 3값)와 결정 메커니즘(4값) 두 축이 UI/모델 사이에서 일치하지 않는다.

### 1.3 결론

**Phase 3 진입 OK.** 단, IA 진입 전에 *deferred 분류*와 *IA 계약 5개 포인트*를 잠근다 (본 PR).

---

## 2. Deferred Triage (3-bucket)

### 2.1 분류 기준

| Bucket | 정의 | Phase 3 영향 |
|---|---|---|
| **A. Phase 3 Blocker** | IA에서 보여주는 *의미 자체*를 바꾸는 항목. Phase 3 화면을 만들고 나서 고치면 IA를 두 번 뒤엎게 된다. | Phase 3 IA Skeleton(PR B) **착수 전 또는 함께** 닫는다. |
| **B. Absorb into Phase 3** | UI 세부 품질·a11y·copy·작은 상태 표시 개선. Phase 3 화면 작업 안에서 자연스럽게 같이 처리. | Phase 3 화면별 PR(C 이후)에 내장. 별도 PR 생성 금지. |
| **C. Post Phase 3** | IA와 무관한 운영·최적화·장기 cleanup·법무 검토 필요 항목. | backlog로 유지. Phase 3 종료 후 별도 사이클. |

### 2.2 항목 분류

#### Bucket A — Phase 3 Blocker (의미·계약 변경)

| # | 항목 | 근거 | 처리 방식 |
|---|---|---|---|
| A1 | **`Transaction` 단위 결정 메커니즘 보존 필드 결정** (예: `Transaction#classification_source` 또는 동등) | ADR-0007 §2: "거래 단위로 결정 메커니즘을 보존할 필드가 필요. 보존 방식은 본 ADR 범위 밖, 별도 마이그레이션 ADR로 결정." 현재 `_category_source_chip`은 decision 4값을 받을 준비가 됐으나 호출자(`_category_cell`)가 항상 nil을 전달 → ADR-0007 §1의 약속이 dormant. | **[ADR-0011](../decisions/ADR-0011-transaction-classification-source.md) closure** (2026-05-16). `classification_source` 컬럼 신설 + 4값 잠금 + nullable + backfill 없음. *Set 로직*은 후속 PR. |
| A2 | **결정 메커니즘 4값 vs 매핑 출처 3값의 UI 라벨 정합성** | `category_mappings/_mapping_row.html.erb`: `manual`→"수동", `import`→"학습", `gemini`→"AI". ADR-0007 §1.2와 합치되지만 `mapping_match` decision의 tooltip이 "학습됨"이라 *import-origin 매핑*과 *user-taught manual 매핑*이 같은 단어("학습")로 충돌할 수 있음. Phase 3 §3.4 "학습된 매핑" 섹션은 ADR-0004 4번 탭에 노출됨 — 이때 어휘가 모호하면 사용자 신뢰가 깨진다. | **[ADR-0011](../decisions/ADR-0011-transaction-classification-source.md) §Decision 5 closure** (2026-05-16). `config/locales/ko.yml` 키 사전 합의: `transactions.classification_source.*` ("학습 매핑"/"키워드"/"AI 추천"/manual_set은 빈 라벨)와 `category_mappings.source.*` ("직접 등록"/"가져온 매핑"/"AI 학습 매핑")로 분리, 두 축이 *같은 단어를 공유하지 않음*. 실제 view i18n 치환은 후속 PR. |
| A3 | **검토 인덱스 진입 라우트의 권한 계약** | ADR-0004 §"ReviewsController 콜백 정정 (필수)": 현재 `:set_parsing_session`이 모든 액션에서 호출됨 → `reviews#index`는 `:set_parsing_session` `except: [:index]`, `:require_workspace_write_access` `except: [:show, :index]` 필요. 본 정정 없이 IA Skeleton(PR B)에서 `reviews#index`만 추가하면 `member_read` 멤버가 검토함 진입 불가. | **ADR-0004에 이미 결정 명시.** PR B에서 콜백 정정과 인덱스 신설을 *같은 PR* 안에서 처리한다. 본 PR은 ADR-0004 §"필수" 문구를 PR B 체크리스트로 흡수. |
| A4 | **`DuplicateConfirmation` 워크스페이스 스코핑** | ADR-0004 §"필수": `DuplicateConfirmation`은 자체 `workspace_id`가 없고 `parsing_session`을 통해 간접 연결. 인덱스에서 단순 `pending` scope만 부르면 cross-tenant leak. | **ADR-0004에 쿼리 패턴 명시.** PR B 체크리스트로 흡수. |
| A5 | **`needs_review` scope 의미 사용 강제** | ADR-0004 §"왜 needs_review인가": `ParsingSession#review_status`의 기본값이 `"pending_review"`라 `status`가 pending/processing/failed일 때도 동일 값을 가질 수 있음. 인덱스에서 `where(review_status: "pending_review")` 직접 호출은 미처리·실패 세션을 검토 큐에 섞음. | **ADR-0004에 이미 결정.** PR B 체크리스트로 흡수. |
| A6 | **purge 상태 노출 semantics 검증** | `ProcessedFile#blob_purged?` 기반 `_blob_purged_badge` "원본 만료"가 ADR-0002 정책(180일 후 자동 purge)과 정렬되어 있는지, Phase 3 IA(거래 목록·세션 카드·검토 상세)에서 어떤 화면에 노출할지 결정. 사용자 신뢰 배지이므로 *실제 purge 완료* semantics와 *UI 노출 시점*이 일치해야 함. | **본 PR §4.5 IA contract 항목으로 결정.** 코드 변경 없음, 노출 매트릭스만 잠금. |
| A7 | **AI 동의 상태와 IA의 관계** | `Workspace.ai_consent_acknowledged_at` nil이면 파싱 진입 차단(parsing_sessions_controller). Phase 3 IA에서 "+ 새로 가져오기" 시트는 검토함에서 진입한다 (ADR-0004) — 동의 미완료 시 검토함 진입은 허용해야 하지만 시트는 동의 화면으로 흘러야 함. | **본 PR §4.5 IA contract 항목으로 결정.** 동의가 IA 1탭 진입 자체를 차단하지 않고, "+ 가져오기" 액션에서만 동의 flow로 분기한다고 명문화. 코드 변경은 PR B에서. |

#### Bucket B — Absorb into Phase 3 (UI 세부, 화면 PR에 내장)

| # | 항목 | 흡수 위치 |
|---|---|---|
| B1 | `_pending_badge`·`_category_source_chip`·`_source_icon` 의 `aria-label`·`role` 점검 | PR B IA Skeleton 또는 화면 단위 PR (Phase 3.2 거래 / 3.3 검토함) |
| B2 | `category_learning_suggestion` 카피 톤·`bg-ai-subtle` 컨트라스트 확인 | PR B 또는 Phase 3.2 거래 PR |
| B3 | empty state 통일 (`shared/_empty_state` 신설은 별도이지만 본 사이클에서 emoji-only로 deferred — open-questions Q7) | Phase 3.2~3.5 각 화면 PR |
| B4 | `parsing_sessions/index`의 AI 동의 inline_alert copy 재확인 (검토함 이동 후 노출 위치 변경) | Phase 3.3 검토함 PR |
| B5 | row inline category 변경 후 학습 제안의 시각적 hierarchy 조정 (현재 `bg-ai-subtle` colspan=6, IA 변경 시 검토함 행의 구조와 정합) | Phase 3.2 또는 3.3 |
| B6 | `_source_metadata_cell` 팝오버 안의 "세션 #ID" 링크가 *옛* helper(`review_workspace_parsing_session_path`)를 가리킴 — ADR-0004는 *옛 path 유지*이므로 변경 불요. 단, 신규 검토함 인덱스로 가는 보조 진입을 같은 팝오버 안에 둘지 결정. | Phase 3.3 검토함 PR |
| B7 | 모바일 하단 탭 4→5탭 전환의 안내 토스트/온보딩 | Phase 3.1 IA Skeleton (모바일 nav 변경 시 함께) |

#### Bucket C — Post Phase 3 (backlog 유지)

| # | 항목 | 사유 |
|---|---|---|
| C1 | ViewComponent 도입 검토 | open-questions Q2: "본 사이클 보류". IA 안정화 후 별도 ADR. |
| C2 | 일러스트 시스템 | open-questions Q7: 본 사이클 deferred, 이모지로 한정. |
| C3 | `UserSetting#theme` 저장 위치 결정 (ADR-0011 후보) | Phase 5 (다크 모드 토글)에서 처리. Phase 3 IA에 영향 없음. |
| C4 | `i18n::JustifyTranslations` lint 도입 | Phase 6 (카피·i18n)에서 처리. |
| C5 | Vision 멀티 기관 정확도 corpus | ADR-0009: dogfood로 점진 검증, 회귀 시 fixture 누적. IA 무관. |
| C6 | Pundit 재검토 | ADR-0001 모니터링 트리거에 따름. IA 무관. |
| C7 | `MCP server 등록 방법` 검증 | current-state Needs audit. 운영 영역, IA 무관. |
| C8 | 텍스트 경로의 Gemini 카테고리 폴백 적용 여부 | current-state Needs audit. AI 파이프라인 변경, IA와 분리. |
| C9 | `_amount` 채택 확산 (모든 금액 표기) | Phase 4 Hero & Variance에서 자연 진행. |

### 2.3 분류 원칙 — "왜 deferred 전체 선처리는 비추천인가"

deferred를 모두 먼저 처리하려 하면 실제로는 Phase 2.1 / 2.2가 무한히 늘어난다. 이유:

- Bucket B는 *Phase 3 화면 구조가 정해진 뒤*에 처리하는 것이 자연스럽다. Phase 2 안에서 따로 PR을 만들면 Phase 3에서 한 번 더 손대게 되어 *중복 작업*이 된다.
- Bucket C는 IA와 무관하므로 지금 처리해도 Phase 3 진입 시점을 미루는 것뿐이다.
- Bucket A만이 Phase 3 진입 *전*에 closure가 필요한 진짜 deferred다. 이는 **본 PR에서 잠그고**, A1/A2처럼 마이그레이션·ADR이 필요한 항목은 별도 *작은* ADR PR로 분리한다.

---

## 3. Phase 3 IA Scope

본 절은 Phase 3에서 *건드릴 화면*과 *건드리지 않을 범위*를 명시한다. ADR-0004 §Decision 5탭이 골격이다.

### 3.1 In Scope (Phase 3에서 처리)

| 영역 | 변경 | 근거 |
|---|---|---|
| 모바일 하단 탭 | 4탭 → 5탭 (홈/거래/검토함/카테고리/더보기) | ADR-0004 |
| 데스크탑 nav | 사이드바 또는 상단 nav를 모바일 5탭과 매칭 | ADR-0004 |
| 라우트 | `GET /workspaces/:id/reviews` (`reviews#index`) **신설** | ADR-0004 §Decision |
| 라우트 | `parsing_sessions/:id/review` (`reviews#show`) **유지** (북마크·외부 링크 호환) | ADR-0004 §Decision |
| ReviewsController | `set_parsing_session` `except: [:index]`, `require_workspace_write_access` `except: [:show, :index]` | ADR-0004 §"필수" |
| ParsingSessions IA | `parsing_sessions/index`의 입력 폼(3-way) → 검토함의 "+ 새로 가져오기" 시트로 *이동* | ui-redesign-plan §3.3 |
| ParsingSessions 라우트 | 기존 path는 유지 (deprecate 결정은 Phase 3~7 이후 별도 ADR) | ADR-0004 §"라우트 매핑" |
| 검토함 UI | 세그먼트 탭 `[파싱 결과 N | 중복 후보 M]` 신설 | ADR-0004 §Decision |
| 워크스페이스 스위처 | 모바일에도 노출 (`ContextHeader` 우측) | ui-redesign-plan §3 |
| 더보기 탭 | 신규 (`/workspaces/:id/more`) — 워크스페이스/AI 설정/내 계정/도구/위험한 작업 그룹 | ui-redesign-plan §3.5 |
| 카테고리 탭 | 카테고리 + "학습된 매핑" 섹션 결합 (현재 `categories/index` + `category_mappings/index` 통합) | ui-redesign-plan §3.4 |
| Bucket A 전 항목 | 본 §2.2 Bucket A 처리 | 본 문서 §2.2 |
| Bucket B 전 항목 | 화면 단위 PR에 내장 | 본 문서 §2.2 |

### 3.2 Out of Scope (Phase 3에서 *하지 않음*)

| 영역 | 사유 |
|---|---|
| Hero/Variance 카드 (`_hero_stat`, `_variance_card`, `_review_inbox_card`) | Phase 4 |
| `RecurringPaymentDetector` 결과 카드화 | Phase 4 |
| 다크 모드 토글 / `UserSetting#theme` 마이그레이션 | Phase 5 |
| 컨트라스트 감사·키보드 단축키 / focus ring 통일 | Phase 5 |
| `ko.yml` 대규모 카피 치환 | Phase 6 (단, Bucket A2의 사전적 키 합의는 본 PR/PR B에서) |
| 메트릭 측정 baseline / 검토 완주율 등 | Phase 7 |
| Vision 멀티 기관 fixture 확장 | ADR-0009: dogfood / 회귀 시 |
| ViewComponent 도입 | open-questions Q2 |
| 일러스트 시스템 | open-questions Q7 |
| 텍스트 경로 Gemini 카테고리 폴백 | current-state Needs audit, 별도 ADR 필요 |
| Excel/PDF/CSV/HTML/이메일/크롤러 입력 | PRD 명시 비기능 요구사항 |

### 3.3 Phase 3 첫 slice(PR B) 권장 산출물

PR B "Phase 3 IA Skeleton"의 골조:

1. `GET /workspaces/:id/reviews` 라우트 + `reviews#index` 액션 (`set_parsing_session` / `require_workspace_write_access` 콜백 정정 동시).
2. `reviews#index` 뷰 — 세그먼트 탭 골조만 (구체 row 디자인은 화면 PR에서).
3. 모바일 하단 탭 5탭 + 데스크탑 nav 5탭 매칭.
4. `parsing_sessions/index`의 입력 폼을 검토함의 "+ 새로 가져오기" 액션으로 *이동* (라우트는 유지, 화면만 빈 큰).
5. Bucket A1(`Transaction#classification_source` 또는 동등) — **ADR-0011 머지 후라면 본 PR에 마이그레이션 적용**, 아직이면 본 PR은 *컬럼 없이* 진행하고 `_category_source_chip` 호출에서 decision은 nil로 유지 (Phase 3.2 화면 PR에서 컬럼 적용).
6. Bucket A2(어휘 합의) — `ko.yml` 키 사전 정의 (실제 치환은 Phase 6 또는 화면 PR에서 점진).

PR B에서 *하지 않을* 것: 화면 디테일·메트릭 카드·hero·다크 모드.

---

## 4. IA 진입 전 검토 — 5개 contract 포인트

본 절은 Phase 3 IA가 *사용자 신뢰를 깨지 않게* 잠가야 할 5개 계약을 정리한다. 일부는 ADR로 이미 결정되어 있어 참조만, 일부는 본 PR에서 합의가 필요하다.

### 4.1 CategoryMapping explicit opt-in 학습 흐름 (ADR-0007 §4)

**현재 상태** (#167 머지 후):

- 인라인 카테고리 변경 → `_category_learning_suggestion_row`가 `bg-ai-subtle` 톤으로 행 아래 삽입.
- "예" 클릭 → `CategoryLearningSuggestionsController#create` → `CategoryMapping(source: "manual", match_type: "exact")` 생성.
- "아니오" 또는 닫기 → DOM에서 제거 (서버 호출 없음).

**Phase 3 영향**:

- 검토함(ADR-0004)에서도 동일하게 동작해야 한다 (현재 `_transaction_row`는 양쪽에서 공유 — #161).
- 검토함의 행에서 학습 제안이 뜰 때 *colspan*과 `bg-ai-subtle` 톤이 새 IA의 row 구조와 충돌하지 않는지 PR B에서 검증.
- 학습이 시작되면 다음 동일 가맹점부터 `mapping_match`로 진입 → 결정 메커니즘 마크가 노출되어야 약속 완결. **A1이 닫히지 않으면 약속이 깨진다.**

**결정**: A1을 Phase 3 IA Skeleton 착수 전(또는 동시) 닫는다.

### 4.2 결정 메커니즘 vs CategoryMapping#source 의미 분리 (ADR-0007 §1)

**현재 상태**:

- 모델: `CategoryMapping#source ∈ {import, gemini, manual}` (매핑 출처 = mapping origin).
- 뷰: `_category_source_chip`이 decision 4값을 받을 준비 완료. `_category_cell`은 항상 nil 전달 → chip의 decision 마크 dormant.
- `category_mappings/_mapping_row`는 매핑 출처 3값을 배지로 노출 (manual/import/gemini → 수동/학습/AI).

**Phase 3 영향**:

- ADR-0004 §Decision 4번 탭("카테고리")이 "학습된 매핑" 섹션을 노출 → 매핑 출처 라벨이 사용자에게 처음으로 *대규모로* 보임.
- 동시에 거래 row의 결정 메커니즘 마크가 켜지면, **사용자 입장에서 "학습 매핑(decision)"과 "import 출처 매핑(origin)"의 어휘 충돌**이 발생할 위험.

**결정 (본 PR에서 합의)**:

- 어휘 분리:
  - 결정 메커니즘 (거래 단위, 4값) — `manual_set` / `mapping_match` / `keyword_match` / `gemini_batch` → 사용자 라벨: *(없음)* / "학습 매핑" / "키워드" / "AI 추천"
  - 매핑 출처 (CategoryMapping 단위, 3값) — `manual` / `import` / `gemini` → 사용자 라벨: "직접 등록" / "가져온 매핑" / "AI 학습 매핑"
- 두 축은 *같은 단어를 공유하지 않는다*: `decision == :mapping_match`일 때 tooltip은 "학습 매핑"이고, `mapping.source == "manual"` 배지는 "직접 등록"으로 표기. 코드/카피 치환은 PR B 또는 Phase 3.4 카테고리 화면 PR에서.

### 4.3 거래 row에서 suggestion / source badge / user override 표시

**현재 상태**:

- `_category_cell`은 read-only와 editable 양 모드에서 `_category_source_chip(category: ...)`만 호출 — decision은 항상 nil.
- editable일 때만 dropdown으로 user override 가능.
- override 후 학습 제안 행이 별도 row로 삽입 (`_category_learning_suggestion_row`).

**Phase 3 영향**:

- IA Skeleton에서 거래 row가 검토함·거래·홈(향후 Phase 4)에 동시 노출됨.
- A1(classification_source 필드) 닫힌 후 `_category_cell`은 decision을 chip에 전달하도록 변경 — 이는 *Phase 3 화면 PR* 안에서 처리.
- "어떤 거래가 AI 추천인가"를 한눈에 식별 가능하게 한다는 ADR-0007 §1의 약속이 켜진다.

**결정**: A1 closure를 전제로, PR B에서는 chip 호출만 dormant 유지(nil). 화면 PR에서 decision 도출 헬퍼(또는 모델 메서드)를 함께 추가한다.

### 4.4 `pending_review → committed` 흐름에서 사용자 신뢰를 해치지 않는 상태 표현

**현재 상태**:

- `Transaction#status ∈ {pending_review, committed, rolled_back, ...}` (모델 단위).
- `ParsingSession#review_status` 기본값 `"pending_review"` — 세션이 `status: pending/processing/failed`여도 동일 값 가짐 (ADR-0004 §"왜 needs_review인가").
- `_pending_badge`로 거래 row에 pending dot 표시.

**Phase 3 영향**:

- 검토함 인덱스에서 *검토 가능한* 세션만 노출해야 한다. `where(review_status: "pending_review")` 직접 호출 금지. `ParsingSession.needs_review` (= `completed.pending_review`) 사용 강제.
- 사용자에게 "검토 대기 N건"으로 카운트 노출 시 의미가 흔들리면 1탭 시민화의 *행동 압력*이 거꾸로 노이즈가 됨.

**결정**: ADR-0004 §"왜 needs_review인가"·§"필수"가 권위. PR B 체크리스트에 *그대로* 포함하고 이탈하지 않는다. 본 PR 추가 결정 불필요.

### 4.5 개인정보/purge 상태가 UI에 노출될 때의 정합성

**현재 상태**:

- `ProcessedFile#blob_purged?`는 `blob_purged_at` 컬럼 기반 (ADR-0002 A1).
- `_blob_purged_badge` "원본 만료" 배지가 정의되어 있음.
- AD R-0002 정책: 종결 후 180일 → 자동 purge (A2 daily job).
- AI 동의: `Workspace.ai_consent_required?` → 파싱 진입 차단 (parsing_sessions_controller).

**Phase 3 영향**:

- 검토함 인덱스(ADR-0004)에 *세션 카드*가 보일 때 purge된 세션은 어떻게 표현되는가?
- AI 동의 미완료 워크스페이스에서 검토함 1탭 진입은 허용해야 하지만, "+ 새로 가져오기" 시트는 동의 화면으로 흘러야 한다.

**결정 (본 PR에서 합의)**:

- **purge 노출 매트릭스 (Phase 3 IA에서)**:
  - 거래 row의 `_source_metadata_cell` 팝오버 안 "세션 #ID" 링크 옆: **노출 (기존 동작 유지)**.
  - 검토함 인덱스의 세션 카드: 노출. 단, 검토함 인덱스에 들어오는 세션은 `needs_review` scope 이므로 본질적으로 committed/rolled_back/discarded는 제외 — purge 시각화는 *세션 상세*(reviews#show)에서 주로 의미를 갖는다.
  - 거래 상세(transactions): 거래에 첨부된 이미지 ProcessedFile이 purged면 배지 노출.
  - 거래 목록의 카테고리·금액 등 *핵심 도메인*에는 노출 금지 (시각적 노이즈).
- **AI 동의 게이트 위치**: 검토함 *인덱스* 진입 허용. 동의 게이트는 "+ 새로 가져오기" 액션 또는 `parsing_sessions#create / text_parse`에서만 (현재 동작 유지). 검토함 1탭 시민화가 동의 미완료 사용자에게 검토 작업을 *볼 수 있게* 하는 것은 가족·팀 공유 환경에서 자연스럽다 (다른 멤버의 검토를 read-only로 볼 수 있어야 함).

코드 변경은 PR B 이후 화면 PR에서. 본 PR은 매트릭스 잠금만.

---

## 5. 작업 순서 권장안

| PR | 제목 | 산출물 | 크기 |
|---|---|---|---|
| **PR A (본 PR)** | Phase 3 IA Preflight / Deferred Triage | 본 문서 + `current-state.md` priority 갱신 + `code-map.md` 참조 추가. 코드는 *문서 정합성 한정*. | 작음 (docs only) |
| **PR A.1 (있다면)** | ADR-0011 — `Transaction` 결정 메커니즘 보존 필드 | Bucket A1 closure. 컬럼 신설 vs `source_metadata` JSON 선택. ADR + 마이그레이션 1개. | 작음 |
| **PR B** | Phase 3 IA Skeleton | `reviews#index` 신설 + 콜백 정정 + 모바일 5탭 + 데스크탑 nav 매칭 + `parsing_sessions/index` 입력 폼 이동. Bucket A3~A5 closure. | 중간 |
| **PR C 이후** | 화면별 구현 — 거래 / 검토함 / 카테고리 / 더보기 | 화면 단위 작은 PR. Bucket B 각 항목을 *해당 화면 PR에서* 흡수. | 화면당 작음 |

PR A.1은 *옵션*이다. 결정 메커니즘 컬럼 신설을 **Phase 3 화면 PR(예: Phase 3.2 거래)** 안에 함께 넣고 ADR도 그 PR에 동봉하는 선택도 가능 — 단 그 경우 화면 PR이 본 PR 하나에서 ADR + 마이그레이션 + 화면 + chip 호출 변경을 모두 담아 커지므로 *분리 권장*.

---

## 6. Phase 3 진입 게이트 (checklist)

PR B 머지 직전에 본 체크리스트로 게이트한다:

- [ ] Bucket A1: 결정 메커니즘 보존 필드가 결정되었거나 (ADR-0011), 본 사이클 dormant 유지 결정이 명시 ADR로 기록됨.
- [ ] Bucket A2: 결정 메커니즘 ↔ 매핑 출처 어휘가 ko.yml 키 사전으로 합의됨 (구현 PR은 분리 가능).
- [ ] Bucket A3: `ReviewsController` 콜백 정정이 PR B에 포함됨.
- [ ] Bucket A4: `DuplicateConfirmation`의 워크스페이스 스코핑 쿼리가 PR B에 포함됨.
- [ ] Bucket A5: `needs_review` scope 사용이 PR B에 포함됨.
- [ ] Bucket A6: purge 노출 매트릭스 (§4.5)에서 이탈하지 않음.
- [ ] Bucket A7: AI 동의 게이트 위치 (§4.5)에서 이탈하지 않음.
- [ ] Phase 3 Out of Scope (§3.2) 항목 중 PR B에 *우발적으로* 포함된 것이 없음.

---

## 7. 위험 & 완화

| 위험 | 영향 | 완화 |
|---|---|---|
| 본 PR이 정의한 IA contract와 실제 구현이 어긋남 | 중 | 본 문서를 PR B의 description에 *체크리스트 형태로* 인용. PR B 리뷰에서 게이트로 동작. |
| Bucket A1을 deferred하면 chip decision 마크가 영구히 dormant 상태로 굳음 | 중 | A1을 ADR로 기록하면 *deferred 결정 자체*가 명시화되어 향후 다시 들어올 때 손실 없음. |
| 본 PR을 "문서 작업"으로 흘려 보내고 Phase 3 화면을 곧장 시작 | 중 | PR B 체크리스트가 본 문서를 강제 인용하도록 PR 템플릿/리뷰에서 점검. |
| Phase 2 deferred 중 Bucket C가 사용자 cognitive load를 키우고 있어 IA만 바꾸면 회귀 인상이 남을 위험 | 저 | Phase 7 회고에서 측정. 회고 결과로 별도 hygiene 사이클 결정. |

---

## 8. 결론

- **Phase 2 deferred 전체 선처리 금지.**
- **Phase 3 진입 OK**, 단 IA Skeleton(PR B) 착수 전에 본 문서가 정한 Bucket A 항목들을 닫는다.
- **본 PR**은 *결정 문서 + triage 표 + IA scope + contract 5점* 잠금. 코드 변경은 문서 정합성에 한정.

---

## 참고

- 디스커버리: `docs/discovery/2026-05-15-ui-redesign-plan.md`
- 디스커버리: `docs/discovery/2026-05-15-design-system-synthesis.md`
- 디스커버리: `docs/discovery/2026-05-15-design-system-open-questions.md`
- ADR: `docs/decisions/ADR-0003` ~ `ADR-0010`
- 현재 상태: `docs/context/current-state.md`, `docs/code-map.md`
- 본 문서는 디스커버리이며 stale될 수 있다. 권위는 ADR.
