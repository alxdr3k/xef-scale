# ADR-0007: 카테고리 출처 시각화

## Status

Accepted

## Date

2026-05-15

## Context

xef-scale의 자동 카테고리화는 4단계 폴백 우선순위로 작동한다 (`PRD.md`, `docs/categorization.md`, `app/models/category_mapping.rb`):

1. `CategoryMapping` (merchant + description + amount, 4단계 우선순위)
2. `Category#keyword` 부분 매칭
3. `GeminiCategoryService` (이미지 경로에서만, 미분류 잔여분 일괄 추천)
4. 사용자 수동 변경

현재 UI(`app/views/transactions/_transaction_row.html.erb`)는 카테고리만 표시할 뿐, **어떤 단계에서 결정되었는지를 보여주지 않는다**. 사용자는 다음을 추적할 수 없다:

- "왜 이 거래가 이 카테고리로 자동 분류되었나?"
- "AI가 추천한 카테고리인가, 내가 학습시킨 매핑인가?"
- "이 카테고리를 바꾸면 학습이 되나?"

이는 두 가지 디자인 원칙과 충돌한다:
- **X4 AI 별도 채널** (synthesis): Gemini 결과는 시각적·언어적으로 격리되어야 함. 현재는 manual·gemini·mapping이 동일하게 표시.
- **뱅샐 P8 예측 수치엔 근거 캡션**: 자동 결과에는 출처가 같이 있어야 신뢰.

또한 사용자가 카테고리를 변경할 때 `CategoryMapping`이 *자동 학습*되는데(`source: "manual"`), 이 사실도 UI에 안내되지 않는다.

## Decision

**모든 거래의 카테고리 표시에 출처를 함께 노출한다.**

세부 결정:

1. **`CategorySourceChip` 컴포넌트 신설** (`app/views/shared/_category_source_chip.html.erb`).
   - 표시 구조: `{카테고리 아이콘} {카테고리명} {source mark}`
   - 4단계 source mark:
     - `manual`: 마크 없음 (기본).
     - `mapping`: 작은 도트 또는 "학습됨" 마이크로 라벨 (사용자가 가르친 매핑).
     - `keyword`: 작은 도트 또는 "키워드" 마이크로 라벨 (Category#keyword 매칭).
     - `gemini`: ✨ 마크 + 점선 테두리 (AI 추천, ADR-0003/0004의 AI 채널 격리 톤).
2. **`Transaction#category_source`** (또는 동등 메타데이터)를 데이터 모델에 보존. 현재 `CategoryMapping#source` 컬럼이 있으나 거래 단위에서 결정 출처는 별도 추적이 필요. 컬럼 추가 또는 `source_metadata` JSON 안에 보존하는 방식은 별도 마이그레이션 PR에서 결정.
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
- `category_source` 추적은 우선 `source_metadata` JSON으로 시작하고, 필요 시 정식 컬럼으로 승격(별도 ADR).
- AI 추천 신뢰도(confidence)를 같이 노출 → 낮은 신뢰도는 "추측이에요" 라벨로 톤 다운.

**테스트/문서 영향**
- `docs/categorization.md` 갱신: 4단계 폴백의 UI 노출 방식 명시.
- `docs/data-model.md` 갱신: `category_source` 추적 필드 (마이그레이션 PR에서).
- 카테고리 변경 후 `CategoryMapping` 자동 생성 동작에 대한 테스트.

## Alternatives considered

1. **출처를 표시하지 않음 (현 상태)** — 거부. AI 채널 격리(X4) 위반. 사용자가 자동 분류를 신뢰할 근거 없음.
2. **출처를 거래 상세 페이지에만 표시** — 거부. 거래 목록에서 한눈에 보이지 않으면 "어떤 거래가 AI 추정인지" 파악 불가.
3. **AI 추천 거래에만 별도 마크 (mapping/keyword 구분 안 함)** — 거부. mapping(사용자 학습)과 keyword(자동 매칭)는 사용자 통제 정도가 다름 — `mapping`은 사용자가 가르친 것, `keyword`는 카테고리 정의에서 자동. 구분 가치 있음.
4. **출처별 색상 분리** — 거부. ADR-0006의 컬러 의미축 5개와 충돌. 도트·라벨·점선 테두리 같은 *형태* 차이로 구분.
5. **자동 학습 alert 없이 묵시적 학습** — 거부. 사용자가 모르고 학습되면 의외성 발생. 명시적 제안이 신뢰에 기여.

## Supersedes

없음.

## References

- 디스커버리: `docs/discovery/2026-05-15-design-system-synthesis.md` (4.2 도메인 컴포넌트, X4)
- 디스커버리: `docs/discovery/2026-05-15-banksalad-ui-deconstruction.md` (P8)
- 디스커버리: `docs/discovery/2026-05-15-ui-redesign-plan.md` (3.2, Phase 2)
- 관련 ADR: ADR-0003, ADR-0004, ADR-0006
- 코드: `app/models/category_mapping.rb`, `app/services/gemini_category_service.rb`, `docs/categorization.md`
