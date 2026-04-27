# Operations

xef-scale의 로컬 개발·환경변수·배포·CI/CD 운영 가이드. 본 문서는 머지된 코드와 워크플로(`.github/workflows/`)를 기준으로 작성됐다. 인프라 자체(Kubernetes 클러스터, ops 레포의 kustomize 구조 등)는 별도 ops 레포에서 관리하므로 그 부분은 `needs audit`로 표시한다.

## 로컬 개발

### 요구사항

- Ruby 3.3.10+ (`.ruby-version`에 명시)
- Bun (JS/CSS 번들)
- SQLite3
- `GEMINI_API_KEY`, `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` (Google OAuth 사용 시)

### 시작

```bash
bundle install
bun install
bin/rails db:create db:migrate db:seed
bin/dev
```

`bin/dev`는 `Procfile.dev`의 `web` (Rails), `js` (esbuild watch), `css` (tailwind CLI watch)를 동시에 실행한다.

### 테스트 로그인 (개발/테스트 전용)

`Rails.env.development?` 또는 `Rails.env.test?`일 때만 `GET /test_login`으로 시드 사용자에 즉시 로그인한다. 프로덕션에서는 라우트가 노출되지 않는다.

## 환경변수

| 키 | 용도 | 어디서 사용? |
|----|------|-------------|
| `GEMINI_API_KEY` | Gemini Flash / Vision API | `AiTextParser`, `GeminiVisionParserService`, `GeminiCategoryService` 생성자 |
| `GOOGLE_CLIENT_ID` | Google OAuth2 | `config/initializers/devise.rb` |
| `GOOGLE_CLIENT_SECRET` | Google OAuth2 | 위와 동일 |
| `RAILS_MASTER_KEY` | 프로덕션 secrets 복호화 | `config/master.key`(로컬) 또는 컨테이너 환경변수 |

비어 있으면 AI 기능은 즉시 `ArgumentError`로 실패한다.

운영 환경의 시크릿은 Doppler `xef-scale` 프로젝트에서 관리한다 (CLAUDE.md 기존 규칙). 로컬에서는 `.env` (dotenv-rails로 development/test에서만 로드).

## 데이터베이스

- 기본: SQLite3 (`storage/`).
- 백그라운드 잡 어댑터: `solid_queue` (DB 기반 큐).
- 캐시: `solid_cache`.
- ActionCable: `solid_cable`.

마이그레이션:

```bash
bin/rails db:migrate
bin/rails db:seed     # FinancialInstitution.seed_default! 등
bin/rails db:reset    # 개발 전용
```

`FinancialInstitution::SUPPORTED_INSTITUTIONS` 시드 8건은 `bin/rails db:seed`(즉 [db/seeds.rb](../db/seeds.rb))의 `FinancialInstitution.seed_default!` 호출로 생성된다. `Rails.env.development?`에서는 같은 파일이 테스트 사용자·기본 워크스페이스·샘플 거래도 만든다.

일괄 가져오기 작업은 [lib/tasks/import.rake](../lib/tasks/import.rake)에 정의된 다음 rake 태스크로 수행한다:

- `import:backup` — Step 0: `DatabaseBackupService`로 SQLite 백업.
- `import:setup_categories` — Step 1: 카테고리 테이블 초기화 + txt 파일에서 카테고리 생성.
- `import:build_mappings` — Step 2: txt 파일에서 `CategoryMapping(source: "import")` 생성.
- `import:transactions` — Step 3: txt 파일에서 거래 import.
- `import:post_backup` — Step 4: import 후 백업.
- `import:all` — 위 5단계를 순차 실행.
- `import:list_backups` — 백업 목록 조회.

일반 사용 흐름은 아니며, 시드/마이그레이션과 별도로 관리한다.

## 백그라운드 잡

- `AiTextParsingJob`, `FileParsingJob`이 `solid_queue`로 인큐된다.
- 별도 워커 프로세스는 `bin/jobs` (Rails 8 기본) 또는 컨테이너의 process 정의에 따른다 — `Procfile.dev`에는 워커가 명시되지 않으므로 in-process executor 또는 Kamal/k8s 배포 정의에서 제공해야 한다 (`needs audit`).

## Gemini API

- Models: `gemini-3-flash-preview`, `gemini-2.5-flash-preview-09-2025`, `gemini-2.5-flash`, `gemini-2.5-flash-lite-preview-09-2025`, `gemini-2.5-flash-lite` (서비스별 폴백 체인 다름 — `docs/ai-pipeline.md` 참조).
- HTTP는 `Net::HTTP`로 직접 호출 (gem 의존성 없음).
- 비활성화 토글: `Workspace.ai_text_parsing_enabled`, `ai_image_parsing_enabled`, `ai_category_suggestions_enabled` 및 `ai_consent_acknowledged_at`.

## Google OAuth

- 라우트: `/users/auth/google_oauth2/callback`.
- 콜백 컨트롤러: `app/controllers/users/omniauth_callbacks_controller.rb` (확인 시 `app/controllers/users/`).
- 로컬 redirect URI: `http://localhost:3000/users/auth/google_oauth2/callback`.

## 배포

### 절대 직접 빌드/배포하지 말 것

`docker build`, `docker push`, ghcr.io 직접 푸시는 금지한다. 모든 빌드와 배포는 GitHub Actions 워크플로가 담당한다 (CLAUDE.md의 운영 규칙).

### 자동 흐름 (push to `main`)

1. `Release` 워크플로 (`.github/workflows/release.yml`)가 `release-please`를 실행.
2. **Release PR이 아닌** 일반 push에서는 `docker-rc` 잡이 RC 이미지를 빌드해 ghcr.io에 push:
   - `${VERSION}-rc.${run_number}` + `latest` 태그.
3. `deploy-stg` 잡이 `.github/workflows/deploy-stg.yml` reusable workflow를 호출한다. 이 워크플로는 cloudflared + SSH로 ops 호스트에 접속, ops 레포의 `apps/<repo>/overlays/stg/kustomization.yaml`의 `newTag`를 RC 태그로 갱신해 커밋·푸시한 후 `kubectl apply -k .` 실행.
4. **Release PR이 머지될 때**는 `docker-release` 잡이 `latest` 이미지를 release 태그로 다시 태깅하고, `deploy-prd` 잡이 동일한 SSH/kubectl 흐름으로 `apps/<repo>/overlays/prd/kustomization.yaml`을 갱신해 PRD에 배포한다.

### 수동 배포

- `.github/workflows/deploy-prd.yml` — `workflow_dispatch`로 PRD에 즉시 `kubectl apply -k apps/<repo>/overlays/prd` 실행.
- `.github/workflows/deploy-stg.yml` — STG 수동 배포. `image_tag` 입력이 있으면 STG `newTag`를 갱신한 뒤 배포하고, 비어 있으면 현재 ops 설정을 그대로 다시 apply한다.

### 환경

| 환경 | 도메인 | Namespace |
|------|--------|-----------|
| stg | stg-scale.xeflabs.com | apps-stg |
| prd | scale.xeflabs.com | apps-prd |

ops 레포 경로: `~/ws/xeflabs/ops/apps/xef-scale/overlays/{stg,prd}` (workspace 루트 CLAUDE.md 참조).

수동 kubectl apply (필요 시):

```bash
kubectl apply -k ~/ws/xeflabs/ops/apps/xef-scale/overlays/stg
kubectl apply -k ~/ws/xeflabs/ops/apps/xef-scale/overlays/prd
```

`KUBECONFIG=~/.kube/config-hetzner` 가 필요하다 (workspace CLAUDE.md).

## CI

`.github/workflows/ci.yml`은 PR마다 실행되는 4개 잡:

- `scan_ruby` — `bin/brakeman --no-pager` + `bin/bundler-audit`.
- `lint` — `bin/rubocop -f github` (rubocop 캐시 활용).
- `test` — `bin/rails db:test:prepare test`.
- `system-test` — `bin/rails db:test:prepare test:system`. 실패 시 `tmp/screenshots`를 아티팩트로 업로드.

E2E (Playwright)는 현재 CI 잡이 없다.

## 트러블슈팅

| 증상 | 원인 후보 | 1차 조치 |
|------|----------|---------|
| 텍스트 붙여넣기 후 세션이 곧장 `failed`로 전환 | `GEMINI_API_KEY` 미설정 (잡은 정상 종료, 세션만 fail) | env 확인, Doppler에서 동기화. 잡 로그에서 `[AiTextParsingJob] Unexpected error` 메시지로 식별 가능 |
| 이미지 업로드가 "지원하지 않는 파일 형식" 거부 | 확장자 외 콘텐츠 타입 / 매직 바이트 불일치 | 실제 이미지인지 확인 (HEIC ↔ JPEG 변환 등) |
| 검토 화면에서 commit이 alert로 거부 | 미해결 `DuplicateConfirmation` 존재 | 중복 일괄 결정 후 다시 commit |
| 카테고리가 매번 Gemini로 분류됨 | `CategoryMapping` 학습이 안 됨 | `category_mappings` 테이블 확인. 텍스트 경로에서는 처음부터 Gemini를 호출하지 않으므로, 텍스트 SMS는 keyword 매칭 또는 사용자 직접 입력으로 학습 필요 |
| AI 기능이 동의 페이지로 계속 리다이렉트 | `Workspace.ai_consent_acknowledged_at`이 nil | 워크스페이스 설정 페이지에서 동의 |

## Needs audit (운영 측면)

- 워커 프로세스 정의 — k8s manifest / Kamal Procfile에서 어떻게 띄우는지 확인 필요.
- 컨테이너 부팅 시 자동 `db:seed` 실행 여부 (k8s manifest / Kamal 정의에서 확인).
- ActiveStorage blob 보존/삭제 정책 — 파싱 완료 후 원본 이미지 삭제 여부 미검증.
- Gemini API quota / rate limit 모니터링.
- 배포 SSH 호스트(`ssh.xeflabs.com`) / Cloudflare Access 운영 정책.
