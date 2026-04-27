# Code Map

xef-scale 코드의 주요 위치를 빠르게 찾기 위한 인덱스. 디렉토리/파일은 [main 브랜치 기준](../) 실제 경로를 사용합니다.

상태 라벨:
- `implemented` — 구현되어 동작 중
- `planned` — 의도는 있으나 코드 없음
- `needs audit` — 코드는 있으나 본 PR에서 동작 검증을 하지 않았거나 모호함
- `possibly stale` — 다른 문서/주석 기준으로 의심됨

## 입력 진입점

| Path | Purpose | Status |
|------|---------|--------|
| [app/controllers/transactions_controller.rb](../app/controllers/transactions_controller.rb) | 직접 입력 (`new`/`create`)·인라인 편집·CSV 내보내기 | implemented |
| [app/controllers/parsing_sessions_controller.rb](../app/controllers/parsing_sessions_controller.rb) | 텍스트 붙여넣기 (`text_parse`)·이미지 업로드 (`create`)·세션 폐기 (`bulk_discard`) | implemented |
| [app/controllers/reviews_controller.rb](../app/controllers/reviews_controller.rb) | 파싱 세션 검토·커밋·롤백·중복 일괄 해결 | implemented |
| [app/controllers/duplicate_confirmations_controller.rb](../app/controllers/duplicate_confirmations_controller.rb) | 단일 중복 결정 업데이트 | implemented |
| [app/controllers/api/v1/base_controller.rb](../app/controllers/api/v1/base_controller.rb) | API 키 Bearer 인증 + 스코프 검사 | implemented |
| [app/controllers/api/v1/transactions_controller.rb](../app/controllers/api/v1/transactions_controller.rb) | `GET /api/v1/transactions[/:id]`, `POST /api/v1/transactions` | implemented |
| [app/controllers/api/v1/summaries_controller.rb](../app/controllers/api/v1/summaries_controller.rb) | `GET /api/v1/summaries/{monthly,yearly}` | implemented |

## 컨트롤러 (그 외)

| Path | Purpose | Status |
|------|---------|--------|
| [app/controllers/application_controller.rb](../app/controllers/application_controller.rb) | 인증/워크스페이스 set/role 체크 (`can_read?`, `can_write?`, `admin_of?`) | implemented |
| [app/controllers/dashboards_controller.rb](../app/controllers/dashboards_controller.rb) | 월별/연별/캘린더/반복결제 대시보드 | implemented |
| [app/controllers/categories_controller.rb](../app/controllers/categories_controller.rb) | 카테고리 CRUD | implemented |
| [app/controllers/category_mappings_controller.rb](../app/controllers/category_mappings_controller.rb) | 가맹점→카테고리 매핑 CRUD | implemented |
| [app/controllers/workspaces_controller.rb](../app/controllers/workspaces_controller.rb) | 워크스페이스 CRUD + AI 동의 처리 | implemented |
| [app/controllers/workspace_invitations_controller.rb](../app/controllers/workspace_invitations_controller.rb) | 초대 토큰 생성/조인 | implemented |
| [app/controllers/workspace_memberships_controller.rb](../app/controllers/workspace_memberships_controller.rb) | 멤버 역할 변경/제거 | implemented |
| [app/controllers/notifications_controller.rb](../app/controllers/notifications_controller.rb) | 알림 목록/읽음 표시 | implemented |
| [app/controllers/allowances_controller.rb](../app/controllers/allowances_controller.rb) | 용돈 거래 인덱스/일괄 갱신 | implemented |
| [app/controllers/comments_controller.rb](../app/controllers/comments_controller.rb) | 거래 댓글 CRUD | implemented |
| [app/controllers/user_settings_controller.rb](../app/controllers/user_settings_controller.rb) | 사용자 설정 (제외 가맹점 등) | implemented |
| [app/controllers/concerns/date_param_sanitization.rb](../app/controllers/concerns/date_param_sanitization.rb) | year/month 파라미터 검증 | implemented |
| [app/controllers/test_sessions_controller.rb](../app/controllers/test_sessions_controller.rb) | 개발/테스트 환경 전용 로그인 | implemented (dev/test only) |

## 모델

| Path | Purpose | Status |
|------|---------|--------|
| [app/models/user.rb](../app/models/user.rb) | Devise + OmniAuth, 워크스페이스 권한 헬퍼 | implemented |
| [app/models/workspace.rb](../app/models/workspace.rb) | 멀티테넌트 루트, AI 토글/동의 | implemented |
| [app/models/workspace_membership.rb](../app/models/workspace_membership.rb) | 역할 (owner/co_owner/member_write/member_read) | implemented |
| [app/models/workspace_invitation.rb](../app/models/workspace_invitation.rb) | 초대 토큰 | implemented |
| [app/models/transaction.rb](../app/models/transaction.rb) | 거래 — status 머신, payment_type, source_type, soft delete | implemented |
| [app/models/category.rb](../app/models/category.rb) | 카테고리 — `keyword` 부분 매칭 | implemented |
| [app/models/category_mapping.rb](../app/models/category_mapping.rb) | 가맹점→카테고리 매핑 — 4단계 우선순위, dedup_signature | implemented |
| [app/models/parsing_session.rb](../app/models/parsing_session.rb) | 파싱 세션 + 검토 상태 머신 (commit/rollback/discard) | implemented |
| [app/models/processed_file.rb](../app/models/processed_file.rb) | 업로드 파일 — 이미지 검증 + 매직 바이트 sniff | implemented |
| [app/models/duplicate_confirmation.rb](../app/models/duplicate_confirmation.rb) | 중복 후보·결정 | implemented |
| [app/models/notification.rb](../app/models/notification.rb) | 인앱 알림 | implemented |
| [app/models/comment.rb](../app/models/comment.rb) | 거래 댓글 | implemented |
| [app/models/allowance_transaction.rb](../app/models/allowance_transaction.rb) | 거래의 용돈 마킹 (조인 모델) | implemented |
| [app/models/budget.rb](../app/models/budget.rb) | 워크스페이스 월 예산 | implemented |
| [app/models/api_key.rb](../app/models/api_key.rb) | API 키 — HMAC digest, 스코프 (`read`/`write`) | implemented |
| [app/models/financial_institution.rb](../app/models/financial_institution.rb) | 금융기관 + 8개 시드 | implemented |

## 서비스

| Path | Purpose | Notes |
|------|---------|-------|
| [app/services/ai_text_parser.rb](../app/services/ai_text_parser.rb) | 텍스트 → 거래 (Gemini Flash, 4모델 폴백, JSON schema) | implemented |
| [app/services/image_statement_parser.rb](../app/services/image_statement_parser.rb) | 업로드된 이미지를 다운로드해 Vision으로 전달, 결과 정규화 | 기본 institution_identifier=`shinhan_card` |
| [app/services/gemini_vision_parser_service.rb](../app/services/gemini_vision_parser_service.rb) | Gemini Vision 호출 — 신한카드 명세서 양식 프롬프트 | needs audit (다른 기관 정확도) |
| [app/services/gemini_category_service.rb](../app/services/gemini_category_service.rb) | 미분류 거래 일괄 카테고리 추천 | implemented (이미지 경로에서만 호출) |
| [app/services/duplicate_detector.rb](../app/services/duplicate_detector.rb) | 동일 워크스페이스 거래와 중복 비교 | implemented |
| [app/services/recurring_payment_detector.rb](../app/services/recurring_payment_detector.rb) | 반복 결제 패턴 탐지 (대시보드용) | implemented |
| [app/services/database_backup_service.rb](../app/services/database_backup_service.rb) | SQLite 백업 헬퍼 | implemented (호출: `lib/tasks/import.rake`) |

## 잡

| Path | Purpose | Status |
|------|---------|--------|
| [app/jobs/ai_text_parsing_job.rb](../app/jobs/ai_text_parsing_job.rb) | 텍스트 붙여넣기 비동기 파싱 + 매핑/keyword 카테고리화 + 중복 감지 | implemented |
| [app/jobs/file_parsing_job.rb](../app/jobs/file_parsing_job.rb) | 이미지 비동기 파싱 + 3단계 카테고리화 + 중복 감지 | implemented |
| [app/jobs/application_job.rb](../app/jobs/application_job.rb) | ActiveJob base | implemented |

큐 백엔드: `solid_queue` (Rails 8 기본). 별도 워커 프로세스 또는 인-프로세스 실행은 환경 설정에 따른다.

## 뷰 / 프론트엔드

| Path | Purpose |
|------|---------|
| [app/views/parsing_sessions/](../app/views/parsing_sessions/) | 업로드/붙여넣기 폼, 세션 리스트 카드/행 |
| [app/views/reviews/](../app/views/reviews/) | 파싱 세션 검토 페이지 |
| [app/views/transactions/](../app/views/transactions/) | 거래 인덱스/폼/turbo_stream 응답 |
| [app/views/dashboards/](../app/views/dashboards/) | 캘린더/월별/연별/반복결제 대시보드 |
| [app/javascript/](../app/javascript/) | Stimulus 컨트롤러 |
| [app/assets/stylesheets/application.tailwind.css](../app/assets/stylesheets/application.tailwind.css) | Tailwind 4 엔트리 |

JS 번들링: bun + esbuild. CSS: tailwind CLI. 시작은 `bin/dev` (Procfile.dev 사용).

## 데이터베이스

| Path | Purpose |
|------|---------|
| [db/schema.rb](../db/schema.rb) | 권위 있는 현재 스키마 |
| [db/migrate/](../db/migrate/) | 마이그레이션 (이력) |
| [db/seeds.rb](../db/seeds.rb) | 기본 시드 |

## 라우팅

| Path | Purpose |
|------|---------|
| [config/routes.rb](../config/routes.rb) | 모든 웹/API 라우트 |
| [mcp-server.json](../mcp-server.json) | REST API → MCP tool 래퍼 정의 |

## 인증 콜백

| Path | Purpose |
|------|---------|
| [app/controllers/users/omniauth_callbacks_controller.rb](../app/controllers/users/omniauth_callbacks_controller.rb) | Devise + Google OAuth2 콜백 |

## Rake 태스크 / lib

| Path | Purpose | Status |
|------|---------|--------|
| [lib/tasks/import.rake](../lib/tasks/import.rake) | 일괄 가져오기 — DB 백업 → 카테고리 매핑(`source: "import"`) → 거래 import. `DatabaseBackupService` 단일 호출 지점. | implemented |
| [db/seeds.rb](../db/seeds.rb) | `FinancialInstitution.seed_default!` 호출 + 개발 환경 샘플 사용자/거래 생성 | implemented |

## 테스트

| Path | Purpose |
|------|---------|
| [test/controllers/](../test/controllers/) | 컨트롤러/요청 테스트 (API v1 포함) |
| [test/models/](../test/models/) | 모델 단위 테스트 |
| [test/services/](../test/services/) | 파서·중복 감지·반복결제 탐지 테스트 |
| [test/jobs/](../test/jobs/) | 잡 통합 테스트 (`ai_text_parsing_job_test.rb`, `file_parsing_job_test.rb`) |
| [test/system/](../test/system/) | Capybara 시스템 테스트 |
| [test/integration/](../test/integration/), [test/migrations/](../test/migrations/), [test/benchmarks/](../test/benchmarks/) | 보조 테스트 |
| [test/fixtures/](../test/fixtures/) | 픽스처 |
| [e2e/](../e2e/) | Playwright E2E 스펙 (`*.spec.ts`) |

## CI / 배포

| Path | Purpose |
|------|---------|
| [.github/workflows/ci.yml](../.github/workflows/ci.yml) | brakeman, bundler-audit, rubocop, rails test, system-test |
| [.github/workflows/release.yml](../.github/workflows/release.yml) | release-please + Docker RC 빌드 + STG reusable workflow 호출 + Release 태그 + PRD 배포 |
| [.github/workflows/deploy-stg.yml](../.github/workflows/deploy-stg.yml) | STG 배포 reusable workflow (`workflow_call`) + 수동 배포 (`workflow_dispatch`) |
| [.github/workflows/deploy-prd.yml](../.github/workflows/deploy-prd.yml) | 수동 PRD 배포 (`workflow_dispatch`) |
| [Dockerfile](../Dockerfile) | 프로덕션 이미지 (Ruby 3.3.10-slim, jemalloc) |
| [release-please-config.json](../release-please-config.json), [.release-please-manifest.json](../.release-please-manifest.json) | release-please 설정 |

배포 인프라(k8s, kustomize, kubeconfig)는 별도 ops 레포(`~/ws/xeflabs/ops`)에서 관리. 자세한 흐름은 [operations.md](operations.md).

## Needs audit

| Path | Reason |
|------|--------|
| [app/services/gemini_vision_parser_service.rb](../app/services/gemini_vision_parser_service.rb) | 프롬프트가 신한카드 양식에 종속 — 다른 기관 명세서 정확도 미측정 |
| [app/views/financial_institutions/](../app/views/financial_institutions/) (있다면) | UI 노출 여부 확인 필요 |
