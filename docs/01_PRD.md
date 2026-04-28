# 01 PRD — xef-scale

Rails 기반 지출 추적 앱. 한국 금융기관의 거래 내역을 워크스페이스 단위로 입력, 검토, 분류, 조회한다.

이 문서는 제품 계약을 `REQ-###` / `NFR-###` 단위로 정리한다. 구현 세부는 [02_HLD.md](02_HLD.md)와 [current/](current/)를 따른다.

## Problem

한국 금융기관의 카드/은행 지출 내역은 SMS, 앱 화면, 카드 명세서 등 여러 표면에 흩어져 있다. 사용자는 이를 빠르게 거래 장부로 모으고, 가족/팀 워크스페이스에서 검토·분류·조회할 수 있어야 한다.

## Users & Goals

- 주요 사용자: 개인, 가족, 소규모 팀/워크스페이스의 지출 관리 사용자.
- 사용자 목표: 직접 입력 또는 AI 파싱으로 거래를 빠르게 등록하고, 중복·분류를 검토한 뒤 월별/연별 지출을 조회한다.
- 운영 목표: 입력 표면을 제한해 유지보수성을 지키고, AI 호출은 동의/토글/결정적 fallback으로 통제한다.

## Scope

### In scope

- 직접 입력(`manual`) 웹 거래 생성.
- 금융 문자/SMS 텍스트 붙여넣기(`text_paste`) AI 파싱.
- 명세서 스크린샷 이미지 업로드(`image_upload`) AI 파싱.
- API key 기반 read/write API.
- 파싱 결과 검토, 중복 해결, commit/rollback/discard.
- 카테고리 매핑, keyword 매칭, 이미지 경로의 Gemini 카테고리 fallback.
- 워크스페이스 기반 멀티테넌트 권한.
- 거래 조회, 필터, 검색, CSV export, 월별/연별 summary.

### Out of scope

- Excel `.xls/.xlsx`, CSV, PDF, HTML 명세서 업로드.
- 이메일(SMTP/IMAP), 크롤러, 마이데이터 API, 로컬 디렉토리 watcher 기반 수집.
- 이미지 파서의 모든 금융기관 명세서 정확도 보장. 현재 Vision prompt는 신한카드 이용대금 명세서에 맞춰져 있으며, 확장은 별도 결정이 필요하다.

## Functional Requirements

| ID | Requirement | Priority | Acceptance |
|---|---|---|---|
| REQ-001 | 사용자는 웹 UI에서 거래를 직접 입력할 수 있고, 직접 입력 거래는 검토 세션 없이 즉시 `committed` 상태로 저장된다. | must | AC-001 |
| REQ-002 | 사용자는 금융 문자/SMS 텍스트를 붙여넣어 AI 파싱 세션을 만들 수 있고, 결과 거래는 `pending_review` 상태로 저장된다. | must | AC-002 |
| REQ-003 | 사용자는 허용된 이미지 형식의 명세서 스크린샷을 업로드해 AI 파싱 세션을 만들 수 있고, 결과 거래는 `pending_review` 상태로 저장된다. | must | AC-003 |
| REQ-004 | API key 사용자는 `read` 스코프로 거래/summary를 조회하고, `write` 스코프로 거래를 생성할 수 있다. API write 거래는 즉시 `committed` 상태로 저장된다. | must | AC-004 |
| REQ-005 | 사용자는 파싱 세션의 거래를 검토한 뒤 commit, rollback, discard할 수 있다. | must | AC-005 |
| REQ-006 | 파싱 세션 commit은 pending duplicate가 남아 있으면 거부되어야 하며, 중복 결정은 commit/rollback 결과에 반영되어야 한다. | must | AC-006 |
| REQ-007 | 거래 카테고리는 `CategoryMapping`, `Category#keyword`, 이미지 경로의 Gemini fallback 순서로 결정된다. 텍스트 경로는 Gemini 카테고리 fallback을 호출하지 않는다. | must | AC-007 |
| REQ-008 | 모든 거래, 카테고리, 세션, API key 데이터는 워크스페이스 경계 안에 있어야 하며 권한 없는 사용자는 읽기/쓰기/관리 작업을 할 수 없다. | must | AC-008 |
| REQ-009 | 사용자는 거래 목록을 기간/카테고리/검색어로 필터링하고 CSV로 export할 수 있다. | should | AC-009 |
| REQ-010 | AI 기능은 워크스페이스별 토글과 AI 동의 게이트를 따른다. | must | AC-010 |
| REQ-011 | 스코프 밖 입력 파일/경로는 허용하지 않는다. 특히 이미지 업로드는 확장자, content type, magic bytes, 크기 제한을 검증한다. | must | AC-011 |

## Non-functional Requirements

| ID | Category | Requirement | Measurement |
|---|---|---|---|
| NFR-001 | security | API token은 원문 저장 없이 digest로 저장하고, revoked/invalid token은 인증되지 않아야 한다. | AC-012 |
| NFR-002 | privacy | AI 호출이 가능한 입력 경로는 워크스페이스 AI 동의와 기능별 토글을 통과해야 한다. | AC-010 |
| NFR-003 | tenant isolation | 다른 워크스페이스의 거래/카테고리/API 데이터가 조회·수정되지 않아야 한다. | AC-008, AC-004 |
| NFR-004 | maintainability | 라우트/스키마 reference는 `docs/generated/*`로 생성하며 손으로 편집하지 않는다. | `bin/rake docs:generate`, Doc Freshness CI |

## Initial Metrics

- 파싱 성공률: `ParsingSession#success_count / total_count`.
- 중복 의심 비율: duplicate count / parsed count.
- 미분류 → Gemini 카테고리 추천 적중률.
- commit 성공/실패 수.

측정 위치와 대시보드 정의는 아직 제품 계약으로 확정하지 않았다. [Q-003](07_QUESTIONS_REGISTER.md#q-003-초기-지표를-어디에서-어떻게-측정할-것인가)를 따른다.

## Related Docs

- [02_HLD.md](02_HLD.md)
- [current/RUNTIME.md](current/RUNTIME.md)
- [current/DATA_MODEL.md](current/DATA_MODEL.md)
- [current/AI_PIPELINE.md](current/AI_PIPELINE.md)
- [current/CATEGORIZATION.md](current/CATEGORIZATION.md)
