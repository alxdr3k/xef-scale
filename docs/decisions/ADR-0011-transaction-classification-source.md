# ADR-0011: Transaction 결정 메커니즘 보존 필드 — `classification_source` 컬럼 신설

## Status

Accepted

## Date

2026-05-16

## Context

[ADR-0007](ADR-0007-category-source-visualization.md) §1은 카테고리 결정의 두 축을 분리했다:

1. **결정 메커니즘 (decision mechanism)** — 이번 거래의 카테고리가 *어떻게* 정해졌는가 (4값):
   - `mapping_match` — `CategoryMapping`이 매칭됨
   - `keyword_match` — `Category#keyword`가 매칭됨
   - `gemini_batch` — `GeminiCategoryService` 배치 추천 (이미지 경로만)
   - `manual_set` — 사용자가 명시적으로 지정 (수동 입력 또는 검토 중 변경)
2. **매핑 출처 (mapping origin)** — `CategoryMapping#source ∈ {import, gemini, manual}`. `mapping_match`일 때, 그 매핑이 처음 어떻게 생겼는지.

ADR-0007 §2는 *거래 단위 결정 메커니즘을 보존할 필드*가 필요함을 명시했으나, 보존 방식(별도 컬럼 vs `source_metadata` JSON 안의 키)을 **별도 마이그레이션 ADR로 결정**하라고 위임했다.

[`docs/discovery/2026-05-15-phase-3-ia-preflight.md`](../discovery/2026-05-15-phase-3-ia-preflight.md) §2.2 Bucket A1은 이 결정을 **Phase 3 IA Skeleton(PR B) 착수 전에 닫아야 할 IA 계약 변경**으로 분류했다. 이유:

- 현재 `app/views/shared/_category_source_chip.html.erb`는 `decision` 4값을 받아 마크를 렌더할 준비가 되어 있으나, 호출자(`app/views/shared/transaction_cells/_category_cell.html.erb`)는 항상 nil을 전달 → chip의 decision 마크가 **dormant**.
- Phase 3 IA가 거래 row를 새 화면(검토함·거래·홈)에 *대규모로* 노출하므로, 거래 단위 결정 메커니즘이 데이터 모델에 없으면 ADR-0007 §1의 약속("사용자가 카테고리 결정 근거를 항상 추적 가능")이 깨진 채로 IA가 굳는다.

## Decision

**`transactions` 테이블에 `classification_source` 컬럼을 신설한다 (string, nullable, no default).** 값 도메인은 ADR-0007 §1의 결정 메커니즘 4값으로 잠근다.

세부:

1. **컬럼 명**: `classification_source`.
   - ADR-0007 §2가 예시로 든 이름을 그대로 채택해 두 ADR 간 연속성을 유지한다.
   - "source"라는 단어가 `Transaction#source_type`(입력 경로), `Transaction#source_metadata`(import hint), `CategoryMapping#source`(매핑 출처)와 어휘 충돌 가능 — 본 ADR은 `classification_source`가 *결정 메커니즘*임을 명시하고, UI 라벨은 `ko.yml`로 분리한다 (§Decision 5).
2. **타입·제약**: `string`, nullable, no default. Index 추가 (분석·필터 쿼리 대비).
3. **값 도메인** (4값, `Transaction::CLASSIFICATION_SOURCES` 상수로 잠금, 순서는 ADR-0007 §1.1을 따른다):
   - `mapping_match` (1단계)
   - `keyword_match` (2단계)
   - `gemini_batch` (3단계, 이미지 경로만)
   - `manual_set` (수동)
4. **모델 validation**: `inclusion: { in: CLASSIFICATION_SOURCES }, allow_nil: true`. nullable인 이유는 §6.
5. **UI 라벨 (Bucket A2 어휘 합의)** — `config/locales/ko.yml`에 결정 메커니즘 4값과 매핑 출처 3값을 *서로 다른* 키 사전으로 분리:
   - 결정 메커니즘 라벨: `transactions.classification_source.{manual_set, mapping_match, keyword_match, gemini_batch}`
     - `manual_set` → (사용자 라벨 없음, chip 마크 없음)
     - `mapping_match` → "학습 매핑"
     - `keyword_match` → "키워드"
     - `gemini_batch` → "AI 추천"
   - 매핑 출처 라벨: `category_mappings.source.{manual, import, gemini}`
     - `manual` → "직접 등록"
     - `import` → "가져온 매핑"
     - `gemini` → "AI 학습 매핑"
6. **본 ADR이 결정하지 *않는* 것 (다음 PR로 이월)**:
   - 호출지점(컨트롤러·잡)에서 `classification_source`를 *언제·어떻게* set할지의 구체 로직. 이는 Phase 3 IA Skeleton(PR B) 또는 별도 PR에서 처리한다. 본 ADR은 *데이터 모델 계약*까지만 잠근다.
   - 기존 거래의 backfill 전략. 기존 거래의 `classification_source`는 nil 유지 (정보 부족 → 추정 금지). chip은 decision nil이면 마크를 렌더하지 않으므로 (= `manual_set` 동등) 시각적 회귀 없음.

## Consequences

**긍정**

- `_category_source_chip`의 decision 4값 dormant 상태가 *해소될 길*이 열림 — 호출지점에서 컬럼을 읽어 그대로 전달 가능.
- 결정 메커니즘이 별도 컬럼이라 `source_metadata` JSON(import/parser hint)과 의미가 *섞이지 않음*.
- 매핑 출처(`CategoryMapping#source`)와 결정 메커니즘(`Transaction#classification_source`)이 데이터 모델 단위로 명시 분리 → ADR-0007 §1.2의 두 축 분리가 데이터에서도 강제됨.
- 어휘가 ko.yml로 분리되어 매핑 출처의 "수동/학습/AI" 배지와 결정 메커니즘의 "학습 매핑/키워드/AI 추천" 마크가 **같은 단어를 공유하지 않음** → 사용자 혼동 방지.

**부정**

- 새 컬럼이 추가되지만 *값을 채우는 로직은 다음 PR* → 본 PR 머지 후 한 사이클 동안 컬럼이 항상 nil. 그 기간에 chip 마크는 여전히 dormant.
- 기존 거래 backfill을 *명시적으로 안 함* → 과거 거래에 대해서는 영구히 nil. 이를 *과거 거래는 manual_set로 추정하여 backfill*하면 잘못된 정보를 표시할 위험이 있어 채택 안 함.
- 컬럼 이름의 "source" 어휘 중복은 코드 가독성 부담 — UI에서는 ko.yml 라벨로 격리하나 코드 리뷰 시 주의 필요.

**완화**

- 본 ADR은 *데이터 모델 계약*까지만. 다음 PR에서 set 로직을 적용할 때 본 ADR §Decision 3의 값 도메인을 그대로 사용.
- 백필 안 함 결정을 ADR과 마이그레이션 주석에 명시 → 향후 "왜 nil이 많은가" 회귀 질문에 답이 박혀 있음.

**테스트/문서 영향**

- 모델 validation 테스트: 4값만 허용 + nil 허용.
- 마이그레이션 테스트: 컬럼/index 존재 검증.
- `docs/data-model.md` 갱신: `Transaction` 컬럼 목록에 추가.
- `docs/categorization.md` 갱신: 결정 메커니즘 4값이 데이터 모델에 잠겨 있음을 명시.
- `docs/code-map.md` 갱신: 마이그레이션 파일 인덱스에 추가.
- `docs/discovery/2026-05-15-phase-3-ia-preflight.md` §2.2 Bucket A1·A2: 본 ADR로 closure 표시 (별도 PR에서 갱신 가능).

## Alternatives considered

1. **`source_metadata` JSON 안의 키로 보존** — 거부. ADR-0007 §2가 "의미가 다른 데이터를 섞으면 혼동"이라 경고. `source_metadata`는 *import/parser hint*용이라 결정 메커니즘과 정의가 다르고, JSON 키는 schema 강제·index·쿼리가 어려움.
2. **별도 테이블 (`transaction_classifications`)** — 거부. 1:1 관계인데 테이블을 쪼개면 조회 비용만 증가. 결정 메커니즘이 거래 변경 시 함께 갱신되므로 같은 row에 두는 것이 자연스럽다.
3. **enum (Rails enum)으로 정의** — 검토 후 보류. Rails enum은 default·integer 매핑·자동 scope를 제공하지만, 현재 `Transaction#payment_type`은 enum, `status`/`source_type`은 단순 string + `inclusion` validation으로 혼재. 본 ADR은 후자 패턴(`source_type`)을 따라 일관성 유지. enum 채택은 후속 일괄 정합 시 별도 결정.
4. **현재 nil 채로 두고 컬럼 신설 보류** — 거부. `_category_source_chip`의 decision 슬롯이 영구 dormant가 되어 ADR-0007 §1 약속이 깨진 채로 굳음. Phase 3 IA에서 거래 row가 대규모 노출되므로 *지금* 잠그는 것이 최저 비용.
5. **컬럼 이름 `category_decision` 또는 `classification_mechanism`** — 검토 후 거부. 의미는 더 명확하나 ADR-0007 §2가 명시한 예시 이름(`Transaction#classification_source`)과 어긋남. 연속성과 후속 PR 리뷰 비용을 우선해 ADR-0007의 이름을 채택.
6. **결정 메커니즘 4값 + `unclassified` 추가** — 거부. `category_id`가 nil이면 자연스럽게 unclassified이므로 별도 값 불필요. 4값 모두 `category_id`가 *있을 때*의 결정 근거.

## Supersedes

없음.

## References

- 상위 ADR: [ADR-0007](ADR-0007-category-source-visualization.md) (카테고리 출처 시각화 — §1.1 결정 메커니즘 4값, §2 보존 필드 위임)
- 디스커버리: [`docs/discovery/2026-05-15-phase-3-ia-preflight.md`](../discovery/2026-05-15-phase-3-ia-preflight.md) §2.2 Bucket A1, A2; §4.1, §4.2, §4.3
- 코드: `app/models/transaction.rb`, `app/views/shared/_category_source_chip.html.erb`, `config/locales/ko.yml`
