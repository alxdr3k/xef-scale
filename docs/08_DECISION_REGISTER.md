# 08 Decision Register

작은 ~ 중간 크기의 결정을 가벼운 레코드로 남긴다.

큰 아키텍처, 제품 스코프, 데이터 경계, AI 정책 결정은 [decisions/](decisions/)의 ADR로 기록한다.

## Decisions

### DEC-001: Current `DatabaseBackupService`는 dev/import 전용 헬퍼이며 운영 백업 계약이 아니다

- Date: 2026-04-30
- Status: accepted
- Deciders: engineering
- Supersedes: —
- Superseded by: —
- Resolves: —
- Impacts: `docs/current/OPERATIONS.md`, `docs/04_IMPLEMENTATION_PLAN.md`, `app/services/database_backup_service.rb`, `lib/tasks/import.rake`

**Context**

`DatabaseBackupService`는 `storage/development.sqlite3`를 `storage/backups/`로 단순 복사한다. production은 `primary`, `cache`, `queue`, `cable` SQLite DB를 별도 파일로 사용하고, 현재 서비스는 SQLite online backup, WAL/checkpoint, `PRAGMA integrity_check`, 외부 보관, 보존 정책, 스케줄, 복구 리허설을 제공하지 않는다.

**Decision**

현재 구현을 신뢰 가능한 운영 백업 프로세스로 취급하지 않는다. 이 서비스는 development/import 전용 안전망으로 명시하고, 후속 구현은 기존 development backup 파일명이나 `restore` 메서드 동작과 하위호환성을 보장하지 않아도 된다. `dev` 브랜치의 현재 구현을 최신 기준으로 삼아, 운영 백업은 새 slice에서 environment-aware SQLite backup/restore primitive와 ops 보관 정책으로 재정의한다.

**Rationale**

운영 백업 계약으로 오해하면 실제 장애 시 복구 불능 또는 불완전 복구 위험이 크다. 현재 코드는 import 작업의 로컬 안전망으로는 유용하지만 production 데이터 보호 요구와는 다른 문제를 풀고 있다.

**Consequences**

- 긍정: import 안전망과 운영 백업 책임이 분리된다.
- 긍정: 후속 구현에서 기존 개발용 파일명/API에 묶이지 않고 안전한 backup/restore 인터페이스를 설계할 수 있다.
- 부정: STG/PRD 백업은 아직 구현되지 않았으므로 Q-008 결정 전까지 운영 리스크가 남는다.
- Follow-ups: Slice `OPS-1A.6`, `OPS-1A.7`, `OPS-1A.8`, `OPS-1A.9`; Q-008.

When a question in [07_QUESTIONS_REGISTER.md](07_QUESTIONS_REGISTER.md) is resolved without needing a full ADR, add an entry from [templates/DECISION_ENTRY.md](templates/DECISION_ENTRY.md).
