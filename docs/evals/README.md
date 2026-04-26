# Evals

xef-scale의 파서·카테고리화·검토/커밋·운영 품질을 측정하기 위한 평가 스펙의 홈. 실행 가능한 자동화는 본 PR에서 구현하지 않는다.

## 초기 평가 영역

### 파싱 품질

- 파싱 성공률 (`ParsingSession.success_count / total_count`).
- 거래 개수 정확도 (LLM 응답 vs ground truth).
- 날짜·금액·가맹점 정확도.
- 지원하지 않는 입력 거부 비율 (예: 이미지 외 파일).

### 카테고리 품질

- `CategoryMapping` 적중률 (1단계 hit / 전체 거래).
- `Category#keyword` 적중률 (2단계 hit / 미분류 잔여).
- Gemini 폴백 호출 비율 (이미지 경로 한정).
- 최종 카테고리 vs 사용자가 수정한 카테고리 일치율.
- 미매핑 가맹점 비율.

### 검토 워크플로

- `pending_review → committed` 성공률.
- `DuplicateConfirmation` 비율 (전체 거래 / 세션).
- 미해결 중복 때문에 commit이 거부된 비율.
- 검토 후 `discard` / `rollback` 비율.

### 비용 / 지연

- 세션당 Gemini 호출 수.
- 거래당 Gemini 호출 수.
- 평균 파싱 지연 (`started_at → completed_at`).

## 작성 방법

- `eval-XXX-name.md`로 파일 추가.
- 측정 방법(쿼리/스크립트), 데이터 소스, 결과 보관 위치를 명시.
- 실제 결과는 코드/스크립트 산출물에 두고, 본 디렉토리에는 스펙과 해석을 보관.

## 현재 스펙

(없음 — 본 PR은 평가 인프라를 구현하지 않는다)
