# xef-scale PRD

Rails 기반 지출 추적 앱. Excel/PDF 명세서 자동 파싱이나 이메일 연동, 로컬 디렉토리 감시형 파서 같은 구조는 사용하지 않는다. 사용자는 다음 두 가지 경로로만 거래를 입력한다.

## 입력 경로

1. **금융 문자 붙여넣기**
   - 카드/은행 SMS 텍스트를 웹 UI에 붙여넣는다.
   - `AiTextParsingJob`이 `AiTextParser`(Gemini Flash)로 파싱.
   - 결과는 `pending_review` 상태의 `Transaction`으로 저장되고, 사용자가 검토/확정한다.

2. **명세서 스크린샷 업로드**
   - JPG / PNG / WEBP / HEIC 이미지만 허용.
   - `FileParsingJob` → `ImageStatementParser` → `GeminiVisionParserService`(Gemini Vision) 로 파싱.
   - 현재 Gemini Vision 프롬프트는 **신한카드 이용대금 명세서** 스크린샷에 맞춰져 있다. 다른 기관은 추후 프롬프트/분기 확장.
   - 결과는 `pending_review` 상태의 `Transaction`으로 저장되고, 사용자가 검토/확정한다.

## 명시적 비기능 요구사항

- Excel (.xls/.xlsx), CSV, PDF, HTML 명세서 업로드는 지원하지 않는다. `ProcessedFile` 모델이 모델 레벨에서 이미지 외 확장자/콘텐츠 타입을 거부한다.
- 로컬 디렉토리 감시자(watchdog 등) 아키텍처는 이 제품의 방향이 아니다.
- 이메일(SMTP)/크롤러 기반 수집도 사용하지 않는다.

## 검토 / 확정 흐름

`pending_review → committed` 전이는 다음 조건이 모두 만족돼야 한다.

- `ParsingSession#can_commit?`가 true (processing 완료 + review pending).
- 해당 세션에 `pending` 상태의 `DuplicateConfirmation`이 없어야 한다. 남아 있으면 `ReviewsController#commit`이 거부하고 안내 메시지를 표시한다.
- 사용자가 "거래 내역 반영" 액션을 실행한다.

## 자동 카테고리화

다음 순서로 카테고리를 결정한다.

1. `CategoryMapping` (merchant + description + amount 기반, 4단계 우선순위)
2. `Category#keyword` 부분 매칭
3. 미분류 잔여분은 `GeminiCategoryService`로 일괄 추천

## 워크스페이스 경계

- 모든 데이터는 `Workspace` 스코프. `Transaction`의 `category_id`는 모델 레벨에서 동일 워크스페이스 소속인지 검증한다.
- 역할: `owner`, `co_owner`, `member_write`, `member_read`.

## 지표(초기)

- 파싱 성공률 (세션 기준 `success_count / total_count`)
- 중복 의심 비율
- 미분류 → Gemini 카테고리 추천 적중률
- 커밋 성공/실패

## 비고

이 문서는 현재 구현의 요약본이다. 상세 아키텍처는 `docs/architecture.md`, 카테고리화 로직은 `docs/categorization.md`를 참조한다.
