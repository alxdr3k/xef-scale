# 카테고리화 전략

xef-scale은 거래를 자동으로 분류하기 위해 3단계 카테고리화 전략을 사용합니다.

## Why 3단계인가?

단일 방식으로는 정확도, 비용, 속도를 모두 만족시킬 수 없습니다:

| 방식 | 장점 | 단점 |
|------|------|------|
| CategoryMapping (exact) | 100% 정확, 즉시 | 새 상점 처리 불가 |
| Category.keyword | 빠름, 패턴 지원 | 오분류 가능 |
| Gemini AI | 새 상점 처리 | API 비용, 지연 |

**결론**: 순차적으로 시도하여 AI 호출을 최소화하고, 학습된 매핑을 재사용합니다.

## 3단계 매칭 흐름

```
1단계: CategoryMapping (exact match)
   │    ✓ 이전에 학습된 상점-카테고리 매핑
   │    ✓ source: import/gemini/manual
   │
   │    매핑 발견? → 해당 카테고리 사용 (종료)
   ▼
2단계: Category.keyword (partial match)
   │    ✓ 카테고리별 keyword 필드 (쉼표 구분)
   │    예: "식비" → "식당,음식,배달,마라탕,치킨"
   │
   │    키워드 매칭? → 해당 카테고리 사용 (종료)
   ▼
3단계: GeminiCategoryService (AI 분류)
   │    ✓ 미분류 거래들을 배치로 처리
   │    ✓ 결과를 CategoryMapping으로 저장 (source: gemini)
   │    ✓ 다음 동일 상점은 1단계에서 처리
   ▼
결과
```

## CategoryMapping 구조

```ruby
# app/models/category_mapping.rb

SOURCES = %w[import gemini manual]

# 필드
merchant_pattern  # 정확한 상점명 (예: "배달의민족")
category_id       # 매핑된 카테고리
source           # 생성 출처

# 메서드
CategoryMapping.find_for_merchant(workspace, merchant)
```

**source 필드의 의미**:
- `import`: CSV/Excel 파일에서 가져온 매핑
- `gemini`: Gemini AI가 분류한 결과
- `manual`: 사용자가 직접 지정

## Category keyword 매칭

```ruby
# app/models/category.rb

# keyword 필드 예시
"식비" → keyword: "식당,음식,배달,마라탕,치킨,피자"
"교통" → keyword: "주유,택시,지하철,버스,카카오T"

def matches?(text)
  keywords_array.any? { |kw| text.downcase.include?(kw.downcase) }
end
```

## Gemini AI 배치 처리

### Why 배치 처리?

- 개별 호출보다 효율적 (API 비용 절감)
- 한 파일의 미분류 거래들을 한 번에 처리
- 컨텍스트 공유로 일관성 향상

### 프롬프트 설계

```ruby
# app/services/gemini_category_service.rb

# 프롬프트: 한글 가계부 분류 지침 + 카테고리 목록
# temperature=0.1 (결정성 높임)
# 응답 형식: "1. 식비\n2. 교통/자동차\n3. 기타"
```

### 폴백 모델

```ruby
MODELS = [
  "gemini-3-flash-preview",
  "gemini-2.5-flash-preview-09-2025",
  "gemini-2.5-flash",
  "gemini-2.5-flash-lite-preview-09-2025",
  "gemini-2.5-flash-lite"
]
```

첫 번째 모델 실패 시 다음 모델로 자동 폴백합니다.

## 학습 루프

Gemini 분류 결과는 CategoryMapping으로 저장됩니다:

```
첫 번째 파일: "스타벅스" → Gemini → "카페/음료"
                              ↓
                    CategoryMapping 생성 (source: gemini)

두 번째 파일: "스타벅스" → CategoryMapping 히트 → "카페/음료"
                              (AI 호출 불필요)
```

## 구현 위치

| 파일 | 역할 |
|------|------|
| `app/jobs/file_parsing_job.rb` | 3단계 매칭 로직 |
| `app/models/category_mapping.rb` | 매핑 모델 |
| `app/models/category.rb` | keyword 매칭 |
| `app/services/gemini_category_service.rb` | AI 분류 |
