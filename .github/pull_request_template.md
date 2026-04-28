# Summary

<!-- 1-3 lines: what changed and why. -->

## Documentation impact

정책: [docs/DOCUMENTATION.md](../docs/DOCUMENTATION.md). 코드 변경이 thin doc을 건드려야 하면 같은 PR에서 갱신한다.

- [ ] No doc impact
- [ ] Updated product scope (`PRD.md`)
- [ ] Updated current state (`docs/context/current-state.md`)
- [ ] Updated runtime / code-map / data-model docs
- [ ] Updated AI / parser / categorization docs (`docs/ai-pipeline.md`, `docs/categorization.md`) — *AI 호출/프롬프트/모델/카테고리 로직이 미세하게라도 바뀌면 SHA 헤더도 갱신*
- [ ] Updated testing / operations docs
- [ ] Regenerated `docs/generated/*` (`bin/rake docs:generate`)
- [ ] Added or superseded ADR (`docs/decisions/`)
- [ ] Added or updated eval spec (`docs/evals/`)
- [ ] Historical / discovery docs only

## Test plan

- [ ] `bin/rails db:test:prepare test`
- [ ] `bin/rails db:test:prepare test:system`
- [ ] `bin/rubocop` / `bin/brakeman` / `bin/bundler-audit`
- [ ] `bunx playwright test` (UI 변경 시)
