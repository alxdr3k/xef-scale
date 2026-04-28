# CLAUDE.md

Claude Code가 이 레포에서 작업할 때 따라야 할 **Claude 전용 운영 규칙**.

일반적인 구현 컨텍스트(현재 구현·런타임·데이터 모델·테스트/운영 명령)는 [AGENTS.md](AGENTS.md)와 [docs/](docs/)에서 시작하라. 본 문서는 그 위에 Claude 환경에서만 추가로 지켜야 할 안전 규칙을 다룬다.

## 읽기 순서

1. [AGENTS.md](AGENTS.md) — 모든 에이전트 공통.
2. [docs/context/current-state.md](docs/context/current-state.md), [docs/current/CODE_MAP.md](docs/current/CODE_MAP.md), [docs/current/TESTING.md](docs/current/TESTING.md).
3. 본 문서의 Claude 전용 규칙.

## Git 규칙

- PR merge 시 **squash 금지**, 반드시 **merge commit**을 사용한다 (커밋 히스토리 보존).
- Conventional Commits 형식.
- `.claude/`, `CLAUDE.md`, `AGENTS.md` 등 Claude/에이전트 관련 파일 수정은 `chore` 타입을 사용 (예: `chore: update claude operating rules`).

## CI/CD 워크플로우 (필수 준수)

**절대 직접 빌드/배포하지 않는다.** 모든 빌드와 배포는 GitHub Actions가 수행한다.

### 금지

- `docker build` 직접 실행 금지.
- `docker push` 금지.
- ghcr.io에 이미지 직접 push 금지.

### 올바른 흐름

1. Conventional Commits로 커밋한다.
2. dev 브랜치(또는 `claude/*`, `feature/*`)에 push.
3. main으로 PR 생성·머지.
4. release-please가 자동으로 Release PR 생성.
5. Release PR 머지 → Docker 이미지 빌드 + ghcr.io push (CI가 처리).
6. ops 레포에서 `kustomization.yaml` 이미지 태그 자동 갱신 + `kubectl apply` (CI/CD가 처리).

자세한 흐름과 환경/도메인은 [docs/current/OPERATIONS.md](docs/current/OPERATIONS.md). Dockerfile을 수정한다면 직접 빌드하지 말고 커밋 후 CI에 맡긴다. 로컬 테스트는 `bin/dev`.

## Skills / 브라우징 / 외부 도구

- 웹 브라우징은 반드시 `/browse` 스킬(gstack)을 사용한다. `mcp__claude-in-chrome__*` 도구는 사용하지 않는다.
- 라이브러리 문서 조회(`context7`)는 다음 경우에만 사용한다:
  - 에러/경고 발생 시 (특히 deprecation).
  - 최신 버전 기능 사용 시.
  - 불확실하거나 기억이 모호할 때.
- 사용 가능한 스킬 (호출 시 `/skill-name` 형식): `/office-hours`, `/plan-ceo-review`, `/plan-eng-review`, `/plan-design-review`, `/design-consultation`, `/design-shotgun`, `/design-html`, `/review`, `/ship`, `/land-and-deploy`, `/canary`, `/benchmark`, `/browse`, `/connect-chrome`, `/qa`, `/qa-only`, `/design-review`, `/setup-browser-cookies`, `/setup-deploy`, `/retro`, `/investigate`, `/document-release`, `/codex`, `/cso`, `/autoplan`, `/plan-devex-review`, `/devex-review`, `/careful`, `/freeze`, `/guard`, `/unfreeze`, `/gstack-upgrade`, `/learn`.

## 운영 안전

- `git push --force` / `--force-with-lease`, `git reset --hard`, branch 삭제, `--no-verify`, `--no-gpg-sign`은 사용자 명시 승인 없이 실행하지 않는다 (글로벌 규칙).
- main / dev 브랜치 직접 push 금지. PR 흐름을 따른다.
- secret/credential을 노출하는 변경은 사전 확인 필수.

## 작업 위임

복잡한 설계/구현/리뷰 작업은 글로벌 Agent Delegation Policy에 따라 전문 에이전트에 위임한다 (단순 작업은 직접 처리 허용). 본 레포에서 자주 쓰는 매핑:

- 백엔드 설계/구현 → `senior-backend-architect`
- 프론트엔드 설계/구현 → `frontend-architect`
- DB 설계/마이그레이션 → `database-architect`
- 코드 리뷰 → `feature-dev:code-reviewer`
- 코드 탐색 → `Explore`
- 기능 분해/조율 → `project-manager`

## 본 문서가 다루지 않는 것

다음 정보는 다른 문서에 있다. 본 문서에서 중복하지 않는다.

- 제품 정의 → [docs/01_PRD.md](docs/01_PRD.md)
- 현재 구현 상태 → [docs/context/current-state.md](docs/context/current-state.md)
- 아키텍처 / 런타임 / 데이터 모델 → [docs/02_HLD.md](docs/02_HLD.md), [docs/current/RUNTIME.md](docs/current/RUNTIME.md), [docs/current/DATA_MODEL.md](docs/current/DATA_MODEL.md)
- 카테고리화 / AI 파이프라인 → [docs/current/CATEGORIZATION.md](docs/current/CATEGORIZATION.md), [docs/current/AI_PIPELINE.md](docs/current/AI_PIPELINE.md)
- 테스트 / 린트 / 스캔 명령 → [docs/current/TESTING.md](docs/current/TESTING.md)
- 운영 / 환경변수 / 배포 / 트러블슈팅 → [docs/current/OPERATIONS.md](docs/current/OPERATIONS.md)
- 문서 정책 (source-of-truth, thin layer 원칙, 변경 매트릭스) → [docs/DOCUMENTATION.md](docs/DOCUMENTATION.md)
- 모든 에이전트 공통 가이드 → [AGENTS.md](AGENTS.md)
