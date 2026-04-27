# Generated Docs

코드/스키마/마이그레이션/설정에서 자동 생성된 문서가 들어갈 홈.

## 규칙

- 생성된 문서는 **수동으로 편집하지 않는다**. 항상 생성기에서 다시 만든다.
- 생성기 스크립트는 `script/` 또는 Rake 태스크로 둔다.
- 본 PR은 생성기를 만들지 않는다. 향후 후보:
  - `db/schema.rb` → `docs/generated/schema.md`
  - `config/routes.rb` (`bin/rails routes`) → `docs/generated/routes.md`
  - 모델 목록 / 서비스 콜 사이트 / 잡 인벤토리

## 현재 산출물

(없음)
