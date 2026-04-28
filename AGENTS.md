# AGENTS.md

xef-scale에서 작업하는 AI 코딩 에이전트를 위한 간결한 안내. Claude 전용 운영 규칙(배포 안전 규칙 등)은 [CLAUDE.md](CLAUDE.md)에 따로 있다.

## 읽기 순서

일반적인 구현/수정 작업이라면:

1. [docs/context/current-state.md](docs/context/current-state.md)
2. [docs/current/CODE_MAP.md](docs/current/CODE_MAP.md)
3. [docs/current/TESTING.md](docs/current/TESTING.md)
4. 작업과 관련된 코드 (`app/`, `db/`, `config/routes.rb`)
5. 아키텍처/제품 스코프를 바꾸는 경우에만 관련 ADR (`docs/decisions/`)

기본적으로 [docs/design-phase-a.md](docs/design-phase-a.md), [docs/design-phase-b.md](docs/design-phase-b.md), [docs/design/archive/](docs/design/archive/)는 **읽지 않는다**. 이들은 역사적 스냅샷이며 현재 권위가 아니다.

## Source of truth

| 무엇 | 어디 |
|------|------|
| 구현된 동작 | 코드, 테스트, 마이그레이션, [db/schema.rb](db/schema.rb) |
| 제품 스코프 | [docs/01_PRD.md](docs/01_PRD.md) |
| 상위 설계 | [docs/02_HLD.md](docs/02_HLD.md) |
| 현재 구현 요약 | [docs/context/current-state.md](docs/context/current-state.md) 및 `docs/current/` |
| 수락된 결정의 이유 | [docs/decisions/](docs/decisions/) |
| 테스트/린트/스캔 명령 | [docs/current/TESTING.md](docs/current/TESTING.md) |
| 운영/배포 | [docs/current/OPERATIONS.md](docs/current/OPERATIONS.md), [docs/05_RUNBOOK.md](docs/05_RUNBOOK.md) (Claude 전용 안전 규칙은 [CLAUDE.md](CLAUDE.md)) |
| 디스커버리 / 역사 | [docs/discovery/](docs/discovery/), [docs/design/archive/](docs/design/archive/), `docs/design-phase-*.md` (역사) |

## 코드를 변경할 때

문서 정책의 전체 매트릭스와 source-of-truth 우선순위는 [docs/DOCUMENTATION.md](docs/DOCUMENTATION.md)에 있다. 자주 쓰는 규칙만 요약:

- **테스트를 함께 갱신**한다. CI 잡(`test`, `system-test`, `lint`, `scan_ruby`)은 [docs/current/TESTING.md](docs/current/TESTING.md) 참조.
- 런타임 흐름이 바뀌면 [docs/current/RUNTIME.md](docs/current/RUNTIME.md) 갱신.
- 스키마/마이그레이션이 바뀌면 [docs/current/DATA_MODEL.md](docs/current/DATA_MODEL.md) 갱신.
- 모듈/파일 레이아웃이 바뀌면 [docs/current/CODE_MAP.md](docs/current/CODE_MAP.md) 갱신.
- AI/파서/카테고리화 동작이 바뀌면 [docs/current/AI_PIPELINE.md](docs/current/AI_PIPELINE.md) 또는 [docs/current/CATEGORIZATION.md](docs/current/CATEGORIZATION.md) 갱신.
- 입력 경로 / 지원 금융기관이 바뀌면 [docs/01_PRD.md](docs/01_PRD.md), [README.md](README.md), [docs/context/current-state.md](docs/context/current-state.md) 갱신.
- 명령이 추가/변경되면 [docs/current/TESTING.md](docs/current/TESTING.md) 또는 [docs/current/OPERATIONS.md](docs/current/OPERATIONS.md) 갱신.
- 아키텍처/제품 방향이 바뀌면 [docs/decisions/ADR-TEMPLATE.md](docs/decisions/ADR-TEMPLATE.md)로 ADR을 만든다 (이전 ADR/디자인 문서는 supersede).
- 긴 역사적 디자인 문서(`docs/design-phase-*.md`, `docs/design/archive/`, `docs/discovery/`)를 *구현 변경에 맞춰* 다시 쓰지 않는다. 얇은 현재 문서만 패치한다.

## 검증

- 명령은 [docs/current/TESTING.md](docs/current/TESTING.md)에서 가져온다. 새로 만들지 않는다.
- 환경에서 실행할 수 없다면 그 사실과 이유를 PR 본문에 명시.
- 테스트/린트/스캔이 빨갛다면 그대로 PR을 열지 말 것 — 실패를 무시하기 위한 `--no-verify`, `--no-gpg-sign` 등은 사용 금지 (CLAUDE.md 글로벌 규칙).

## 입력 표면 (현재)

스코프에 없는 입력을 추가하지 말 것. 현재 입력 표면은 다음 4가지 뿐이다:

1. 직접 입력 (manual) — `TransactionsController#create`.
2. 텍스트 붙여넣기 (text_paste) — `ParsingSessionsController#text_parse` → `AiTextParsingJob`.
3. 이미지 업로드 (image_upload) — `ParsingSessionsController#create` → `FileParsingJob`.
4. API write (api) — `Api::V1::TransactionsController#create` (`write` 스코프 키 필요).

Excel/PDF/CSV/HTML 명세서, 이메일/IMAP, 크롤러, 디렉토리 워처는 **스코프 밖**이다. 자세히는 [docs/01_PRD.md](docs/01_PRD.md).

## 카테고리화 (현재)

이미지 경로만 Gemini 카테고리 폴백을 호출한다. 텍스트 경로는 `CategoryMapping` + `Category#keyword`까지만. 이를 변경하려면 ADR 필요. 자세히는 [docs/current/CATEGORIZATION.md](docs/current/CATEGORIZATION.md), [docs/current/AI_PIPELINE.md](docs/current/AI_PIPELINE.md).
