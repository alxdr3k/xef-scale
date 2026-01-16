# Deployment Guide - Multi-User Workspace Expense Tracker

This guide covers the complete deployment procedure for the multi-user workspace expense tracking system with allowance privacy features.

## Table of Contents

1. [Pre-Deployment Checklist](#pre-deployment-checklist)
2. [Deployment Procedure](#deployment-procedure)
3. [Rollback Procedure](#rollback-procedure)
4. [Post-Deployment Monitoring](#post-deployment-monitoring)

---

## Pre-Deployment Checklist

### 1. Database Backup

Before deployment, create a complete backup of the production database.

```bash
# Create backup directory if it doesn't exist
mkdir -p /Users/yngn/ws/expense-tracker/backups

# Backup SQLite database with timestamp
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
cp /Users/yngn/ws/expense-tracker/db/expense_tracker.db \
   /Users/yngn/ws/expense-tracker/backups/expense_tracker_${BACKUP_DATE}.db

# Verify backup integrity
sqlite3 /Users/yngn/ws/expense-tracker/backups/expense_tracker_${BACKUP_DATE}.db "PRAGMA integrity_check;"

# Expected output: ok
```

**Backup Verification Checklist:**
- [ ] Backup file created successfully
- [ ] Backup file size matches original (within 5%)
- [ ] SQLite integrity check returns "ok"
- [ ] Backup file is readable and not corrupted

### 2. Migration Testing

Test the database migration in a staging/test environment before production.

```bash
# Create test database copy
cp /Users/yngn/ws/expense-tracker/db/expense_tracker.db \
   /Users/yngn/ws/expense-tracker/db/expense_tracker_test.db

# Run migration on test database
sqlite3 /Users/yngn/ws/expense-tracker/db/expense_tracker_test.db < \
  /Users/yngn/ws/expense-tracker/db/migrations/011_add_workspace_system.sql

# Verify migration success
sqlite3 /Users/yngn/ws/expense-tracker/db/expense_tracker_test.db <<EOF
-- Verify all 4 new tables exist
SELECT name FROM sqlite_master
WHERE type='table'
AND name IN ('workspaces', 'workspace_memberships', 'workspace_invitations', 'allowance_transactions');

-- Verify all triggers exist
SELECT name FROM sqlite_master
WHERE type='trigger'
AND name LIKE 'update_workspace%';

-- Verify data migration - check that all transactions have workspace_id
SELECT COUNT(*) as total_transactions, COUNT(workspace_id) as transactions_with_workspace
FROM transactions;

-- Verify foreign key integrity
PRAGMA foreign_key_check;
EOF
```

**Migration Testing Checklist:**
- [ ] All 4 tables created: `workspaces`, `workspace_memberships`, `workspace_invitations`, `allowance_transactions`
- [ ] All 3 triggers created: `update_workspaces_timestamp`, `update_workspace_memberships_timestamp`, `update_workspace_invitations_timestamp`
- [ ] All existing transactions have `workspace_id` assigned
- [ ] All existing users have default workspace created
- [ ] Foreign key integrity check passes (no errors)
- [ ] Test database queries work correctly

### 3. Environment Variables Verification

Verify all required environment variables are set correctly.

```bash
# Check .env file exists and contains required variables
cd /Users/yngn/ws/expense-tracker

# Required environment variables
grep -E "^(GOOGLE_CLIENT_ID|GOOGLE_CLIENT_SECRET|JWT_SECRET_KEY|FRONTEND_URL|BACKEND_URL)" .env

# Example .env contents:
# GOOGLE_CLIENT_ID=your_google_client_id.apps.googleusercontent.com
# GOOGLE_CLIENT_SECRET=your_google_client_secret
# JWT_SECRET_KEY=your_random_secret_key_min_32_chars
# FRONTEND_URL=http://localhost:5173
# BACKEND_URL=http://localhost:8000
```

**Environment Variables Checklist:**
- [ ] `GOOGLE_CLIENT_ID` set (Google OAuth credentials)
- [ ] `GOOGLE_CLIENT_SECRET` set
- [ ] `JWT_SECRET_KEY` set (minimum 32 characters, random)
- [ ] `FRONTEND_URL` set (e.g., http://localhost:5173 or production domain)
- [ ] `BACKEND_URL` set (e.g., http://localhost:8000 or production domain)
- [ ] All values are production-ready (no test/placeholder values)

### 4. Security Review Checklist

Critical security features that must be verified:

**Allowance Privacy (CRITICAL):**
- [ ] User A's allowances are completely hidden from User B in transaction lists
- [ ] Total amount calculations exclude other users' allowances
- [ ] Monthly summaries respect allowance privacy
- [ ] Category breakdowns respect privacy
- [ ] Allowance list shows only user's own allowances
- [ ] 15/15 allowance privacy tests passing (`test_allowance_privacy.py`)

**Workspace Isolation:**
- [ ] Users can only access workspaces they're members of
- [ ] Transactions are filtered by workspace_id
- [ ] Workspace invitations require valid tokens
- [ ] Cross-workspace data leakage prevented

**Authentication & Authorization:**
- [ ] Google OAuth integration working
- [ ] JWT tokens expire correctly (24 hours default)
- [ ] Protected endpoints require valid authentication
- [ ] Role-based access control (OWNER, CO_OWNER, MEMBER_WRITE, MEMBER_READ)

**Data Validation:**
- [ ] Input validation on all API endpoints
- [ ] SQL injection prevention (parameterized queries)
- [ ] XSS prevention (input sanitization)

### 5. Performance Checks

Verify database indexes and query performance:

```bash
# Check all workspace-related indexes exist
sqlite3 /Users/yngn/ws/expense-tracker/db/expense_tracker.db <<EOF
-- List all indexes related to workspace system
SELECT name, tbl_name FROM sqlite_master
WHERE type='index'
AND (name LIKE '%workspace%' OR name LIKE '%allowance%')
ORDER BY tbl_name, name;
EOF

# Expected indexes:
# idx_workspaces_created_by (workspaces)
# idx_workspaces_active (workspaces)
# idx_workspace_memberships_workspace (workspace_memberships)
# idx_workspace_memberships_user (workspace_memberships)
# idx_workspace_memberships_role (workspace_memberships)
# idx_workspace_memberships_active (workspace_memberships)
# idx_workspace_memberships_user_workspace (workspace_memberships)
# idx_workspace_invitations_token (workspace_invitations)
# idx_workspace_invitations_workspace (workspace_invitations)
# idx_workspace_invitations_active (workspace_invitations)
# idx_allowance_transactions_transaction (allowance_transactions)
# idx_allowance_transactions_user_workspace (allowance_transactions)
# idx_allowance_transactions_workspace (allowance_transactions)
# idx_transactions_workspace (transactions)
# idx_transactions_workspace_date (transactions)
# idx_processed_files_workspace (processed_files)
# idx_processed_files_uploaded_by (processed_files)
```

**Performance Checklist:**
- [ ] All 17 workspace/allowance indexes created
- [ ] Query plan uses indexes (run EXPLAIN QUERY PLAN on critical queries)
- [ ] Database file size is reasonable (< 100MB for typical usage)
- [ ] Response times < 200ms for transaction list queries

### 6. Frontend & Backend Build Verification

Verify both frontend and backend can build successfully:

```bash
# Backend verification
cd /Users/yngn/ws/expense-tracker
python -m pytest tests/ -v --tb=short

# Expected: All tests pass (especially test_allowance_privacy.py - 15/15)

# Frontend build verification
cd /Users/yngn/ws/expense-tracker/frontend
npm install
npm run build

# Expected: Build completes without errors, dist/ directory created
```

**Build Verification Checklist:**
- [ ] Backend tests pass (pytest)
- [ ] Allowance privacy tests pass: 15/15 tests
- [ ] Frontend builds without errors
- [ ] No TypeScript errors
- [ ] No ESLint warnings/errors (critical)
- [ ] Production build size is reasonable (< 5MB)

---

## Deployment Procedure

### Step 1: Pre-Deployment Preparation

```bash
# Navigate to project root
cd /Users/yngn/ws/expense-tracker

# Pull latest changes (if using git)
git pull origin main

# Verify current branch
git branch --show-current
# Expected: main

# Verify latest migration is present
ls -la db/migrations/011_add_workspace_system.sql
```

### Step 2: Stop Running Services

```bash
# Stop backend service (if running)
# Press Ctrl+C in terminal running backend, or:
pkill -f "uvicorn.*main:app"

# Stop frontend dev server (if running)
pkill -f "vite"

# Verify services stopped
ps aux | grep -E "(uvicorn|vite)" | grep -v grep
# Expected: no output
```

### Step 3: Database Migration

**CRITICAL: Create backup before migration (see Pre-Deployment Checklist #1)**

```bash
# Apply migration to production database
cd /Users/yngn/ws/expense-tracker

sqlite3 db/expense_tracker.db < db/migrations/011_add_workspace_system.sql

# Verify migration success
sqlite3 db/expense_tracker.db <<EOF
-- Check tables created
SELECT COUNT(*) as table_count
FROM sqlite_master
WHERE type='table'
AND name IN ('workspaces', 'workspace_memberships', 'workspace_invitations', 'allowance_transactions');
-- Expected: 4

-- Check data migration
SELECT COUNT(*) as total, COUNT(workspace_id) as with_workspace
FROM transactions;
-- Expected: total == with_workspace (all transactions have workspace_id)

-- Check foreign key integrity
PRAGMA foreign_key_check;
-- Expected: no output (no integrity violations)
EOF
```

**Migration Verification Checklist:**
- [ ] Migration completed without errors
- [ ] 4 new tables created
- [ ] All existing transactions have `workspace_id`
- [ ] All existing users have default workspace
- [ ] Foreign key integrity check passes

### Step 4: Backend Deployment

```bash
# Install/update backend dependencies
cd /Users/yngn/ws/expense-tracker
pip install -r requirements.txt

# Verify environment variables loaded
python -c "
import os
from dotenv import load_dotenv
load_dotenv()
required_vars = ['GOOGLE_CLIENT_ID', 'GOOGLE_CLIENT_SECRET', 'JWT_SECRET_KEY', 'FRONTEND_URL']
for var in required_vars:
    assert os.getenv(var), f'Missing {var}'
print('All environment variables loaded successfully')
"

# Run backend in production mode
cd /Users/yngn/ws/expense-tracker
uvicorn backend.main:app --host 0.0.0.0 --port 8000 --workers 4 --log-level info

# Alternative: Run in background with nohup
nohup uvicorn backend.main:app --host 0.0.0.0 --port 8000 --workers 4 --log-level info > backend.log 2>&1 &

# Save PID for later management
echo $! > backend.pid
```

**Backend Deployment Checklist:**
- [ ] Backend starts without errors
- [ ] Health check endpoint responds: `curl http://localhost:8000/health`
- [ ] API documentation accessible: `http://localhost:8000/docs`
- [ ] CORS headers configured correctly
- [ ] Logs show no errors

### Step 5: Frontend Build and Deployment

```bash
# Build frontend for production
cd /Users/yngn/ws/expense-tracker/frontend

# Ensure environment variables set
cat > .env.production <<EOF
VITE_API_URL=http://localhost:8000
VITE_GOOGLE_CLIENT_ID=your_google_client_id.apps.googleusercontent.com
EOF

# Build production bundle
npm run build

# Verify build output
ls -lh dist/
# Expected: dist/ directory with index.html and assets/

# Serve production build (example using serve)
npm install -g serve
serve -s dist -l 5173

# Alternative: Use nginx or other web server to serve dist/ directory
```

**Frontend Deployment Checklist:**
- [ ] Build completes without errors
- [ ] `dist/` directory created
- [ ] `dist/index.html` exists
- [ ] Static assets in `dist/assets/`
- [ ] Frontend accessible at configured URL
- [ ] Google OAuth login works
- [ ] Workspace selector appears after login

### Step 6: Post-Deployment Verification

Run comprehensive verification tests:

```bash
# Backend health check
curl http://localhost:8000/health
# Expected: {"status":"ok"}

# Backend API endpoints check
curl http://localhost:8000/docs
# Expected: OpenAPI documentation HTML

# Test authentication flow (manual)
# 1. Open frontend in browser
# 2. Click "Sign in with Google"
# 3. Complete OAuth flow
# 4. Verify redirect to dashboard
# 5. Check workspace selector in top bar

# Run integration tests
cd /Users/yngn/ws/expense-tracker
python -m pytest tests/test_allowance_privacy.py -v
# Expected: 15/15 tests pass

python -m pytest tests/test_workspace_flow.py -v
# Expected: All tests pass
```

**Post-Deployment Verification Checklist:**
- [ ] Backend health endpoint responds
- [ ] Frontend loads successfully
- [ ] Google OAuth login works
- [ ] Workspace selector displays user's workspaces
- [ ] Transaction list loads (empty or with data)
- [ ] Allowance privacy tests pass (15/15)
- [ ] No errors in browser console
- [ ] No errors in backend logs

---

## Rollback Procedure

If deployment fails or critical issues are discovered, follow this rollback procedure.

### Step 1: Stop Services

```bash
# Stop backend
kill $(cat /Users/yngn/ws/expense-tracker/backend.pid) 2>/dev/null || pkill -f "uvicorn.*main:app"

# Stop frontend (if using serve)
pkill -f "serve.*dist"
```

### Step 2: Database Restoration

```bash
# Find latest backup
ls -lt /Users/yngn/ws/expense-tracker/backups/ | head -5

# Restore backup (replace YYYYMMDD_HHMMSS with actual timestamp)
BACKUP_FILE="expense_tracker_20260115_120000.db"
cp /Users/yngn/ws/expense-tracker/backups/${BACKUP_FILE} \
   /Users/yngn/ws/expense-tracker/db/expense_tracker.db

# Verify restoration
sqlite3 /Users/yngn/ws/expense-tracker/db/expense_tracker.db "PRAGMA integrity_check;"
# Expected: ok

# Verify data
sqlite3 /Users/yngn/ws/expense-tracker/db/expense_tracker.db <<EOF
-- Check if workspace tables exist (should NOT if rollback successful)
SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='workspaces';
-- Expected: 0 (table should not exist after rollback)
EOF
```

### Step 3: Code Revert

```bash
# Revert to previous commit (if using git)
cd /Users/yngn/ws/expense-tracker
git log --oneline -5
# Identify commit before deployment

# Revert to previous version
git checkout <previous_commit_hash>

# Alternative: Revert specific migration commit
git revert <migration_commit_hash> --no-commit
git commit -m "Rollback: Revert workspace system deployment"
```

### Step 4: Service Restart

```bash
# Restart backend with previous version
cd /Users/yngn/ws/expense-tracker
uvicorn backend.main:app --host 0.0.0.0 --port 8000 --workers 4 --log-level info &
echo $! > backend.pid

# Rebuild and restart frontend (if needed)
cd /Users/yngn/ws/expense-tracker/frontend
npm run build
serve -s dist -l 5173 &
```

### Step 5: Post-Rollback Verification

```bash
# Verify backend works
curl http://localhost:8000/health

# Verify database structure (should be pre-migration state)
sqlite3 /Users/yngn/ws/expense-tracker/db/expense_tracker.db <<EOF
SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;
EOF

# Run tests
cd /Users/yngn/ws/expense-tracker
python -m pytest tests/test_transactions_crud_api.py -v
```

**Rollback Verification Checklist:**
- [ ] Services stopped successfully
- [ ] Database restored from backup
- [ ] Database integrity check passes
- [ ] Workspace tables removed (if rollback successful)
- [ ] Code reverted to previous version
- [ ] Services restarted successfully
- [ ] Application functional (pre-deployment state)
- [ ] No data loss verified

---

## Post-Deployment Monitoring

### First 24 Hours Checklist

Monitor the system closely during the first 24 hours after deployment.

#### Hour 1: Immediate Monitoring

```bash
# Monitor backend logs
tail -f /Users/yngn/ws/expense-tracker/backend.log

# Watch for errors
grep -i "error\|exception\|failed" /Users/yngn/ws/expense-tracker/backend.log | tail -20

# Monitor database size
ls -lh /Users/yngn/ws/expense-tracker/db/expense_tracker.db

# Check active connections
lsof -i :8000
```

**Hour 1 Checklist:**
- [ ] No errors in backend logs
- [ ] No exceptions thrown
- [ ] Database size stable
- [ ] Backend responding to requests
- [ ] Frontend accessible

#### Hours 2-4: User Activity Monitoring

**User Actions to Monitor:**
- [ ] User login successful
- [ ] Workspace creation works
- [ ] Workspace switching works
- [ ] Transaction list loads correctly
- [ ] Allowance marking works
- [ ] Allowance privacy enforced (User B cannot see User A's allowances)
- [ ] Total amounts calculated correctly
- [ ] Monthly summary respects privacy

#### Hours 4-24: Stability Monitoring

```bash
# Check for memory leaks
ps aux | grep uvicorn | awk '{print $6}'
# Monitor memory usage over time (should be stable)

# Check database query performance
sqlite3 /Users/yngn/ws/expense-tracker/db/expense_tracker.db <<EOF
-- Enable query timing
.timer on

-- Test critical queries
SELECT COUNT(*) FROM transactions WHERE workspace_id = 1;
SELECT * FROM transactions WHERE workspace_id = 1 ORDER BY transaction_date DESC LIMIT 50;
EOF

# Monitor error rate
grep -c "ERROR" /Users/yngn/ws/expense-tracker/backend.log
# Should be 0 or very low
```

**Hours 4-24 Checklist:**
- [ ] No memory leaks detected
- [ ] Query performance acceptable (< 200ms for transaction list)
- [ ] Error rate low (< 1 error per 1000 requests)
- [ ] No user complaints
- [ ] All features working as expected

### Logging and Monitoring Setup

**Backend Logging Configuration:**

```python
# backend/main.py - Logging setup
import logging

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('backend.log'),
        logging.StreamHandler()
    ]
)
```

**Key Log Events to Monitor:**
- Authentication failures (potential security issues)
- Database query errors
- Allowance privacy violations (should NEVER occur)
- Workspace access violations
- Unhandled exceptions

### Performance Metrics to Watch

**Database Performance:**
```bash
# Transaction list query time (should be < 200ms)
sqlite3 /Users/yngn/ws/expense-tracker/db/expense_tracker.db <<EOF
.timer on
SELECT t.*, c.name as category_name, i.name as institution_name
FROM transactions t
LEFT JOIN categories c ON t.category_id = c.id
LEFT JOIN institutions i ON t.institution_id = i.id
WHERE t.workspace_id = 1
  AND NOT EXISTS (
    SELECT 1 FROM allowance_transactions at
    WHERE at.transaction_id = t.id
      AND at.workspace_id = t.workspace_id
      AND at.user_id != 1
  )
ORDER BY t.transaction_date DESC
LIMIT 50;
EOF
```

**Expected Performance:**
- Transaction list query: < 200ms
- Monthly summary query: < 500ms
- Allowance marking: < 100ms
- Workspace switching: < 100ms

### User Feedback Collection

**Questions to Ask Users:**
1. Can you log in successfully with Google?
2. Do you see your workspaces in the workspace selector?
3. Can you mark transactions as allowances?
4. When marking a transaction as allowance, does it disappear from other users' views?
5. Are total amounts calculated correctly?
6. Are there any errors or unexpected behaviors?

**Critical Issues to Escalate Immediately:**
- Users seeing other users' allowances (PRIVACY VIOLATION)
- Users accessing workspaces they don't belong to (SECURITY VIOLATION)
- Total amounts including other users' allowances (CALCULATION ERROR)
- Authentication failures preventing login

---

## Emergency Contacts and Escalation

### Critical Issues (Escalate Immediately)

- **Privacy violation**: User seeing another user's allowances
- **Security breach**: Unauthorized workspace access
- **Data loss**: Transactions disappearing or corrupted
- **Authentication failure**: Users cannot log in

### Non-Critical Issues (Monitor and Fix)

- Slow query performance (> 500ms)
- UI/UX issues (styling, layout)
- Minor bugs (edge cases)

---

## Deployment Success Criteria

Deployment is considered successful when:

- [ ] All 4 workspace tables created and populated
- [ ] All 17 indexes created
- [ ] All existing data migrated successfully
- [ ] 15/15 allowance privacy tests passing
- [ ] Backend and frontend running without errors
- [ ] User authentication working
- [ ] Workspace functionality working
- [ ] Allowance privacy enforced correctly
- [ ] No errors in logs for first hour
- [ ] User acceptance testing completed successfully

---

## Additional Resources

- **Architecture Documentation**: `/Users/yngn/ws/expense-tracker/docs/ARCHITECTURE.md`
- **Production Readiness Report**: `/Users/yngn/ws/expense-tracker/docs/PRODUCTION_READINESS.md`
- **Migration File**: `/Users/yngn/ws/expense-tracker/db/migrations/011_add_workspace_system.sql`
- **Allowance Privacy Tests**: `/Users/yngn/ws/expense-tracker/tests/test_allowance_privacy.py`
- **API Documentation**: `http://localhost:8000/docs` (after deployment)

---

**Last Updated**: 2026-01-16
**Version**: 1.0.0
**Migration Version**: 011_add_workspace_system
