# Expense Tracker - AI Agent Development Rules

**이 문서는 AI Agent 작업 실행을 위한 규칙 문서입니다. 일반 개발 가이드는 CLAUDE.md를 참조하세요.**

---

## 1. 작업 완료 프로토콜 (MANDATORY)

모든 작업은 다음 순서를 **반드시** 따라야 합니다:

```
1. 기능 구현
2. Git commit (메시지 형식: "Task {task_id}: {description}")
3. 테스트 작성 및 실행
4. 테스트 통과 확인
5. project-manager agent에게 Shrimp 업데이트 위임
6. 사용자에게 완료 보고
```

### 예시: 올바른 작업 완료 흐름

```bash
# 1. 기능 구현 완료

# 2. Git commit
git add .
git commit -m "Task abc123: Implement transactions API"

# 3. 백엔드 테스트 작성 및 실행
pytest tests/test_transactions_api.py -v

# 4. 테스트 통과 확인 (12/12 PASSED)

# 5. project-manager에게 Shrimp 업데이트 위임
Task tool → subagent_type=project-manager → "Task abc123 완료, Shrimp 업데이트 요청"

# 6. 사용자에게 보고
```

### ⚠️ 금지: 테스트 없이 작업 완료

```bash
# ❌ 잘못된 예시
git commit -m "Task abc123: Done"
# (테스트 작성/실행 없이 바로 완료 처리) → 절대 금지
```

---

## 2. 테스트 요구사항 (MANDATORY)

### 백엔드 테스트

**필수 사항:**
- 모든 API 엔드포인트는 단위 테스트 필수
- 통합 테스트: Repository와 Database 상호작용 검증
- 테스트 명령: `pytest tests/ -v`
- 테스트 위치: `tests/test_{module_name}.py`

**예시:**
```python
# tests/test_transactions_api.py
def test_get_transactions_success():
    response = client.get("/api/transactions?year=2026")
    assert response.status_code == 200
    assert len(response.json()["data"]) > 0

def test_get_transactions_unauthorized():
    response = client.get("/api/transactions")  # No JWT
    assert response.status_code == 401
```

### 프론트엔드 테스트

**필수 사항:**
- 모든 페이지는 E2E 테스트 필수
- E2E 프레임워크: Playwright 또는 Cypress
- 테스트 명령: `npm run test:e2e` (설정 필요)
- 테스트 위치: `frontend/tests/e2e/{page_name}.spec.ts`

**예시:**
```typescript
// frontend/tests/e2e/transactions.spec.ts
test('should display transactions table', async ({ page }) => {
  await page.goto('/transactions');
  await expect(page.locator('table')).toBeVisible();
  await expect(page.locator('tbody tr')).toHaveCount.greaterThan(0);
});

test('should filter by year', async ({ page }) => {
  await page.goto('/transactions');
  await page.selectOption('select[name="year"]', '2026');
  await page.waitForResponse('/api/transactions?year=2026');
  // Verify filtered results
});
```

### 테스트 실패 처리

- 테스트 실패 = 작업 미완료
- 테스트를 통과할 때까지 수정 필수
- Shrimp 업데이트 전에 **반드시** 테스트 통과 확인

---

## 3. 파일 연쇄 수정 규칙 (MANDATORY)

특정 파일을 수정하면 관련 파일도 **반드시 함께** 수정해야 합니다.

| 수정하는 파일 | 연쇄 수정 필수 파일 | 이유 |
|---------------|---------------------|------|
| `db/migrations/*.sql` | `src/db/repository.py` | 새 테이블/컬럼 추가 시 Repository 메서드 구현 필요 |
| `backend/api/schemas.py` | `frontend/src/types/index.ts` | API 응답 타입과 FE 타입 동기화 필수 |
| `backend/api/routes/*.py` | `tests/test_*.py` | 새 엔드포인트 추가 시 테스트 작성 필수 |
| `frontend/src/pages/*.tsx` | `frontend/tests/e2e/*.spec.ts` | 새 페이지 추가 시 E2E 테스트 작성 필수 |
| `src/db/repository.py` | `tests/test_*_repository.py` | Repository 메서드 추가 시 단위 테스트 필수 |

### 예시: DB 마이그레이션 후 연쇄 작업

```bash
# 1. 마이그레이션 생성
db/migrations/007_add_categories_table.sql

# 2. Repository 메서드 추가 (필수)
src/db/repository.py → CategoryRepository 클래스 구현

# 3. 테스트 작성 (필수)
tests/test_category_repository.py → 단위 테스트

# 4. API 엔드포인트 (선택)
backend/api/routes/categories.py → GET /api/categories

# 5. FE 타입 동기화 (API 추가 시 필수)
frontend/src/types/index.ts → Category 타입 추가
```

---

## 4. Shrimp Task Manager 통합 규칙

### ⚠️ 절대 금지: 직접 Shrimp MCP 호출

```bash
# ❌ 금지
mcp-cli call shrimp-task-manager/verify_task '{"taskId": "..."}'
mcp-cli call shrimp-task-manager/execute_task '{"taskId": "..."}'
```

### ✅ 올바른 방법: project-manager에게 위임

```typescript
Task tool → subagent_type=project-manager → "다음 작업 완료, Shrimp 업데이트 요청:
- Task ID: abc123
- 완료 내용: ...
- Git commit: ...
- 테스트 결과: 12/12 PASSED"
```

**이유:**
- project-manager는 전체 작업 흐름을 관리
- 의존성 체크 및 다음 작업 자동 시작
- 일관된 작업 추적

---

## 5. Git Commit 규칙

### Commit 메시지 형식

```
Task {task_id}: {description}

{optional detailed explanation}

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

### 예시

```bash
# ✅ 올바른 예시
git commit -m "Task 3947a9bf: Phase2-API Auth router implementation

Implement Google OAuth authentication endpoints with JWT token issuance.
Integrated UserRepository for user lookup and creation.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"

# ❌ 잘못된 예시
git commit -m "fix auth"  # Task ID 누락
git commit -m "Done"      # 설명 불충분
```

### Commit 타이밍

- **1 작업 = 1 commit**
- 작업 완료 직후 바로 commit
- 여러 작업을 한 번에 commit 금지
- 테스트 작성은 같은 commit에 포함 가능

---

## 6. 우선순위 및 품질 기준

### 작업 우선순위

1. **테스트 작성 및 통과** (최우선)
2. 문서화 (API 문서, README 업데이트)
3. 성능 최적화

### 품질 게이트

다음 조건을 **모두** 충족해야 작업 완료:

- ✅ Git commit 완료
- ✅ 테스트 작성 완료
- ✅ 테스트 통과 (100%)
- ✅ 관련 파일 연쇄 수정 완료
- ✅ TypeScript/Python 빌드 오류 없음

---

## 7. 금지 사항 (PROHIBITIONS)

### ⚠️ 절대 금지

1. **테스트 없이 작업 완료**
   - 백엔드 API 추가 → pytest 테스트 필수
   - 프론트엔드 페이지 추가 → E2E 테스트 필수

2. **직접 Shrimp MCP 호출**
   - `mcp-cli call shrimp-task-manager/*` 직접 사용 금지
   - project-manager agent에게 위임

3. **API 스키마 변경 후 FE 타입 미동기화**
   - `backend/api/schemas.py` 변경 → `frontend/src/types/index.ts` 동기화 필수

4. **DB 마이그레이션 후 Repository 미구현**
   - 새 테이블 생성 → Repository 클래스 구현 필수

5. **테스트 실패 상태로 작업 완료**
   - 테스트가 실패하면 수정 후 재실행
   - 모든 테스트 통과할 때까지 작업 미완료

---

## 8. 자주 사용하는 명령어

### 백엔드 테스트

```bash
# 전체 테스트 실행
pytest tests/ -v

# 특정 테스트 파일
pytest tests/test_transactions_api.py -v

# 커버리지 포함
pytest tests/ --cov=src --cov-report=html
```

### 프론트엔드 테스트

```bash
# E2E 테스트 (설정 후)
npm run test:e2e

# 특정 테스트
npm run test:e2e -- transactions.spec.ts

# 헤드리스 모드
npm run test:e2e -- --headless
```

### API 서버 실행

```bash
# 백엔드
cd backend
uvicorn main:app --reload

# 프론트엔드
cd frontend
npm run dev
```

---

## 9. 작업 체크리스트

작업 완료 전 다음을 확인하세요:

- [ ] 기능 구현 완료
- [ ] Git commit 완료 (Task ID 포함)
- [ ] 테스트 작성 완료
- [ ] 테스트 실행 및 통과 (100%)
- [ ] 관련 파일 연쇄 수정 완료
- [ ] 빌드 오류 없음
- [ ] project-manager에게 Shrimp 업데이트 위임
- [ ] 사용자에게 완료 보고

---

## 10. 트러블슈팅

### 테스트 실패 시

1. 에러 메시지 확인
2. 관련 코드 수정
3. 테스트 재실행
4. 통과할 때까지 반복

### API/FE 타입 불일치 시

1. `backend/api/schemas.py` 확인
2. `frontend/src/types/index.ts` 동기화
3. TypeScript 빌드 재실행 (`npm run build`)

### DB 마이그레이션 오류 시

1. 마이그레이션 파일 문법 확인
2. `python3 -m src.db.migrate` 실행
3. `src/db/repository.py`에 메서드 구현
4. 테스트 작성 및 실행

---

**중요:** 이 규칙을 따르지 않으면 작업이 불완전한 상태로 남게 됩니다. 모든 단계를 순서대로 수행하세요.
