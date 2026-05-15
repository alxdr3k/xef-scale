# ADR-0007: 카테고리 출처 시각화

## Status

Accepted

## Date

2026-05-15

## Context

xef-scale의 자동 카테고리화는 3단계 폴백으로 작동한다 (`docs/categorization.md`, `app/models/category_mapping.rb`). 코드 사실(2026-05-15):

```ruby
# app/models/category_mapping.rb
SOURCES = %w[import gemini manual].freeze
```

`CategoryMapping#source`는 **매핑이 어떻게 생겨났는지를 기록하는 메타**이며 (`import`/`gemini`/`manual` 3종), `Category#keyword`는 **CategoryMapping이 아니라 Category 모델의 매칭 키워드 필드**다.

따라서 *카테고리가 결정된 메커니즘*과 *기존 매핑의 출처*는 서로 다른 축이다. 본 ADR은 이 둘을 명확히 분리한다.

1. **결정 메커니즘 (decision mechanism)** — 이번 거래의 카테고리가 어떤 단계에서 정해졌는가:
   - `mapping_match` — `CategoryMapping`이 매칭됨 (1단계)
   - `keyword_match` — `Category#keyword`가 매칭됨 (2단계)
   - `gemini_batch` — `GeminiCategoryService` 배치 추천 (3단계, 이미지 경로만)
   - `manual_set` — 사용자가 명시적으로 지정 (수동 입력 또는 검토 중 변경)
2. **매핑 출처 (mapping origin)** — `mapping_match`일 때, 그 매핑이 처음 어떻게 생겼는지:
   - `CategoryMapping#source ∈ {import, gemini, manual}` (현재 모델 그대로)
   - 즉 결정 메커니즘이 `mapping_match`이면 *어떤 origin의 매핑인지*를 함께 알 수 있다.

현재 UI(`app/views/transactions/_transaction_row.html.erb`)는 카테고리만 표시할 뿐, **결정 메커니즘도 매핑 출처도 보여주지 않는다**. 사용자는 다음을 추적할 수 없다:

- "왜 이 거래가 이 카테고리로 자동 분류되었나?"
- "AI가 추천한 카테고리인가, 내가 학습시킨 매핑인가?"
- "이 카테고리를 바꾸면 학습이 되나?"

이는 두 가지 디자인 원칙과 충돌한다:
- **X4 AI 별도 채널** (synthesis): Gemini 결과는 시각적·언어적으로 격리되어야 함.
- **뱅샐 P8 예측 수치엔 근거 캡션**: 자동 결과에는 출처가 같이 있어야 신뢰.

또한 사용자가 카테고리를 변경할 때 `CategoryMapping`이 자동 생성 가능한데(`source: "manual"`), 이 사실도 UI에 안내되지 않는다.

## Decision

**모든 거래의 카테고리 표시에 결정 메커니즘을 함께 노출한다. 결정 메커니즘과 매핑 출처는 별개 축이며 UI에서도 그렇게 다룬다.**

세부 결정:

1. **`CategorySourceChip` 컴포넌트 신설** (`app/views/shared/_category_source_chip.html.erb`).
   - 표시 구조: `{카테고리 아이콘} {카테고리명} {decision mark}`
   - `decision mark`는 결정 메커니즘별:
     - `manual_set` — 마크 없음 (사용자 직접 지정).
     - `mapping_match` — 작은 도트 또는 "학습됨" 마이크로 라벨. 호버/탭 시 매핑 출처(`import` / `gemini` / `manual`) 노출.
     - `keyword_match` — 작은 도트 또는 "키워드" 마이크로 라벨.
     - `gemini_batch` — ✨ 마크 + 점선 테두리 (AI 추천, X4 AI 채널 격리 톤).
2. **거래 단위 결정 메커니즘 추적**.
   - 거래 단위로 결정 메커니즘을 보존할 필드(예: `Transaction#classification_source`)가 필요. 이 필드는 *결정 메커니즘 4값* 중 하나를 가진다.
   - 보존 방식(별도 컬럼 vs `source_metadata` JSON 안의 키)은 본 ADR 범위 밖. **`Transaction#source_metadata`는 현재 import/parser hint용**이라 의미가 다른 데이터를 섞으면 혼동 — 컬럼 신설을 우선 검토하되 별도 마이그레이션 ADR로 결정.
   - 본 ADR은 *UI 표시 결정*이며 *데이터 모델 결정*은 후속 작업.
3. **AI 추천(`gemini_batch`) 거래는 AIBadgeCard 톤으로 묶어 검토함에서 별도 표시**:
   - 검토함의 파싱 결과 탭에서 AI 추천 카테고리 행은 보라 outline.
   - 사용자가 채택/거부 행동을 명시.
   - 채택 시 `CategoryMapping`이 *학습*되어 다음 거래에서 `mapping_match`로 이동.
3. **AI 추천(`gemini`) 거래는 AIBadgeCard 톤으로 묶어 검토함에서 별도 표시**:
   - 검토함의 파싱 결과 탭에서 AI 추천 카테고리 행은 보라 outline.
   - 사용자가 채택/거부 행동을 명시.
   - 채택 시 `CategoryMapping`으로 *학습* 되어 다음 거래에서 1단계로 이동.
4. **사용자가 카테고리 변경 시 인라인 학습 제안 alert** 노출:
   - 마이크로카피: "다음 같은 가맹점부터는 이 카테고리로 자동 분류할까요?" + [예 / 아니오] 액션.
   - "예" 선택 시 `CategoryMapping` 신설 (`source: "manual"`).
   - X10에 따라 `ko.yml`로 카피 관리.
5. **카테고리 화면(ADR-0004 4번 탭)에 "학습된 매핑" 섹션** 분리 노출.
   - `CategoryMappingRow`에 source badge 표시.
   - 사용자가 매핑을 검토·수정·삭제 가능.

## Consequences

**긍정**
- 사용자가 카테고리 결정 근거를 항상 추적 가능 → AI 신뢰 ↑.
- AI 추천 거래가 시각적으로 분리되어 채택률 측정 가능 (메트릭 baseline).
- 학습 제안 alert로 `CategoryMapping`이 *명시적*으로 학습됨 — 사용자가 "내가 가르치고 있다"는 감각 획득.
- 검토함에서 AI 추천 우선 처리 → 워크플로우 효율.

**부정**
- `CategorySourceChip`이 거래 row를 시각적으로 더 무겁게 만들 수 있음 — 디자인에서 마이크로 라벨 톤 다운 필요.
- `Transaction#category_source` 데이터 모델 추적이 추가 마이그레이션 부담.
- AI 추천 채택률이 노출되어 *Gemini 정확도가 낮으면 신뢰 손실* 발생 가능 — 정확도 모니터링 필요.

**완화**
- chip 디자인을 컴팩트하게 (작은 도트 또는 ✨ 1자).
- 거래 단위 결정 메커니즘 보존은 별도 마이그레이션 ADR로 결정 (컬럼 신설 우선 검토, `source_metadata` JSON 재활용은 의미 혼동 위험 있음).
- AI 추천 신뢰도(confidence)를 같이 노출 → 낮은 신뢰도는 "추측이에요" 라벨로 톤 다운.

**테스트/문서 영향**
- `docs/categorization.md` 갱신: 3단계 폴백의 UI 노출 방식 명시. 결정 메커니즘 vs 매핑 출처 분리도 함께.
- `docs/data-model.md` 갱신: 거래 단위 결정 메커니즘 보존 필드 (별도 마이그레이션 PR에서).
- 카테고리 변경 후 `CategoryMapping` 자동 생성 동작에 대한 테스트.

## Alternatives considered

1. **결정 메커니즘을 표시하지 않음 (현 상태)** — 거부. AI 채널 격리(X4) 위반. 사용자가 자동 분류를 신뢰할 근거 없음.
2. **결정 메커니즘을 거래 상세 페이지에만 표시** — 거부. 거래 목록에서 한눈에 보이지 않으면 "어떤 거래가 AI 추정인지" 파악 불가.
3. **AI 추천 거래에만 별도 마크 (mapping/keyword 구분 안 함)** — 거부. `mapping_match`(과거에 학습된 결과 재사용)와 `keyword_match`(Category#keyword 매칭)는 사용자 통제 정도가 다름.
4. **결정 메커니즘과 매핑 출처를 한 토큰으로 표현** — 거부. *왜 결정됐는지*와 *그 매핑이 어디서 왔는지*는 의미 축이 다름. 한 토큰으로 합치면 본문에서 정정한 GPT 리뷰의 혼동(메커니즘과 출처를 섞은 표기) 재발.
5. **결정 메커니즘별 색상 분리** — 거부. ADR-0006의 컬러 의미축 5개와 충돌. 도트·라벨·점선 테두리 같은 *형태* 차이로 구분.
6. **자동 학습 alert 없이 묵시적 학습** — 거부. 사용자가 모르고 학습되면 의외성 발생. 명시적 제안이 신뢰에 기여.

## Supersedes

없음.

## References

- 디스커버리: `docs/discovery/2026-05-15-design-system-synthesis.md` (4.2 도메인 컴포넌트, X4)
- 디스커버리: `docs/discovery/2026-05-15-banksalad-ui-deconstruction.md` (P8)
- 디스커버리: `docs/discovery/2026-05-15-ui-redesign-plan.md` (3.2, Phase 2)
- 관련 ADR: ADR-0003, ADR-0004, ADR-0006
- 코드: `app/models/category_mapping.rb`, `app/services/gemini_category_service.rb`, `docs/categorization.md`
