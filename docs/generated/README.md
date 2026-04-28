# Generated Docs

코드/스키마/마이그레이션/설정에서 자동 생성된 문서.

## 규칙

- 생성된 문서는 **수동으로 편집하지 않는다**. 항상 생성기에서 다시 만든다.
- 생성기는 `lib/tasks/docs.rake`.
- 본 디렉토리의 산출물은 `bin/rake docs:generate`로 한 번에 갱신한다.

## 갱신

```bash
bin/rake docs:generate         # 모든 산출물
bin/rake docs:generate:routes  # routes.md만
bin/rake docs:generate:schema  # schema.md만
```

코드 변경 PR이 라우팅이나 스키마를 건드렸다면, 같은 PR에서 위 명령으로 산출물을 다시 만들어 commit 한다 (PR template의 "Regenerated `docs/generated/*`" 체크박스).

## 현재 산출물

- [routes.md](routes.md) — `config/routes.rb` 기준 전체 라우트 목록 (출처: `bin/rails routes`).
- [schema.md](schema.md) — `db/schema.rb` 기준 테이블 목록 + 전체 스키마.

## 향후 후보

- 모델 목록 (이름 + 주요 association)
- 서비스 콜 사이트 / Job 인벤토리
- API endpoint 목록 (`Api::V1::*`)
