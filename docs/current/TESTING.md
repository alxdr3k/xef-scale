# Testing

xef-scale의 테스트·린트·보안 스캔 명령. 현재 GitHub Actions CI(`.github/workflows/ci.yml`)에서 실행되는 명령을 기준으로 기록하고, 별도 로컬 helper는 구분해서 적는다. 새 명령을 도입하면 같은 PR에서 본 문서를 갱신.

## Rails 테스트 (Minitest)

```bash
bin/rails db:test:prepare test
```

- `test/models/`, `test/controllers/`, `test/helpers/`, `test/services/`, `test/jobs/`, `test/integration/`, `test/migrations/`, `test/benchmarks/` 등 일반 Minitest 스위트.
- `test/controllers/api/`에 API v1 컨트롤러 요청 테스트 포함.
- 픽스처: `test/fixtures/`.

## 시스템 테스트 (Capybara)

```bash
bin/rails db:test:prepare test:system
```

- CI는 `system-test` 잡을 실행하지만, 현재 `test/system/`에는 커밋된 Capybara 스펙이 없다. 향후 시스템 스펙 실패 시 스크린샷은 `tmp/screenshots`에 저장되어 아티팩트로 업로드된다.

## 린트

```bash
bin/rubocop
```

CI는 `bin/rubocop -f github` 포맷을 사용한다. 설정은 `.rubocop.yml` (`rubocop-rails-omakase` 베이스).

## 보안 스캔

```bash
bin/brakeman --no-pager
bin/bundler-audit
```

CI에서 `scan_ruby` 잡으로 두 명령 모두 실행된다.

## E2E 테스트 (Playwright)

E2E는 `e2e/` 디렉토리에 Playwright 스펙으로 존재하며 CI의 `e2e` 잡에서 실행된다.

```bash
# 의존성 설치
bun install

# Rails 서버 자동 기동 + Chromium 테스트 실행
bunx playwright test
```

- 설정: `playwright.config.ts` — `bin/rails server -p 3000`을 자동으로 띄운다.
- 스펙: `e2e/*.spec.ts` (allowances, dashboard, duplicate, notifications, parsing_session, review-workflow, reviews, rollback, transactions).
- CI는 Node 20에서 `npm install` → `npm run build && npm run build:css` → `npx playwright install --with-deps chromium` → `RAILS_ENV=test bin/rails db:schema:load db:seed` → `npx playwright test` 순서로 실행한다.

## JS / CSS 빌드

`bin/dev`로 개발 서버를 띄우면 Procfile.dev에 따라 Rails + esbuild watch + tailwind watch가 함께 기동된다.

수동 빌드:

```bash
bun install
bun run build       # JS 번들
bun run build:css   # Tailwind CSS
```

## 개발 시작

```bash
bundle install
bun install
bin/rails db:create db:migrate db:seed
bin/dev
```

`bin/setup`은 위 절차를 자동화하는 로컬 helper다. `--skip-server`를 주면 서버를 띄우지 않는다.

## 로컬 CI helper

`bin/ci`는 GitHub Actions workflow가 아니라 로컬 ActiveSupport CI helper다. 현재 `config/ci.rb`는 `bin/setup --skip-server`, `bin/rubocop`, `bin/bundler-audit`, `bun audit`, `bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error`, `bin/rails test`, `RAILS_ENV=test bin/rails db:seed:replant`를 실행한다.

`GEMINI_API_KEY`, `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `RAILS_MASTER_KEY` 등 환경변수는 [OPERATIONS.md](OPERATIONS.md) 참조.

## PR 열기 전 체크리스트

가능한 경우 모두 실행:

- [ ] `bin/rails db:test:prepare test`
- [ ] `bin/rails db:test:prepare test:system`
- [ ] `bin/rubocop`
- [ ] `bin/brakeman --no-pager`
- [ ] `bin/bundler-audit`
- [ ] (UI/플로우 변경 시) `bunx playwright test` 또는 CI와 같은 `npx playwright test`로 관련 스펙 확인

## 명령이 누락되거나 실패할 때

- 현재 워크트리/머신에서 실행 불가하면 PR 본문에 명시.
- `db:test:prepare`은 `config/database.yml` test 환경에 SQLite 기본 경로를 가정한다. 실패 시 SQLite 설치를 확인.
- system 테스트는 Headless 브라우저 환경이 필요. 로컬에서는 `tmp/screenshots`를 확인.

## 테스트 작성 가이드 (참고)

- 새 모델/마이그레이션은 모델 테스트 추가.
- 새 컨트롤러 액션 / 워크스페이스 게이트는 요청 테스트 추가.
- 새 잡/서비스는 잡·서비스 테스트 추가 (Gemini 호출은 mock — 실제 API 호출 금지).
- 시스템/E2E 테스트는 신규 사용자 플로우(특히 `pending_review → committed`, 중복 처리, 동의 게이트)에 추가.
