-- Migration: 011_add_workspace_system.sql
-- Description: Add workspace and allowance management capabilities
-- Date: 2026-01-15
-- Author: Database Architect
-- Task: 4bcefbfd-c60a-4c1d-8d93-e06089fe7df1 - Phase 1.1: Database Migration - Create Workspace Tables

BEGIN TRANSACTION;

-- ============================================
-- UP Migration
-- ============================================

-- ================================================
-- 1. WORKSPACES TABLE
-- ================================================
-- Main workspace entity for multi-user expense tracking
CREATE TABLE IF NOT EXISTS workspaces (
    id INTEGER PRIMARY KEY AUTOINCREMENT,

    -- Basic workspace information
    name TEXT NOT NULL,
    description TEXT,

    -- Ownership and settings
    created_by_user_id INTEGER NOT NULL,
    currency TEXT DEFAULT 'KRW',
    timezone TEXT DEFAULT 'Asia/Seoul',

    -- Status tracking
    is_active BOOLEAN DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (created_by_user_id) REFERENCES users(id) ON DELETE RESTRICT
);

-- Workspace indexes for performance
CREATE INDEX idx_workspaces_created_by ON workspaces(created_by_user_id);
CREATE INDEX idx_workspaces_active ON workspaces(is_active) WHERE is_active = 1;

-- Trigger for workspaces updated_at timestamp
CREATE TRIGGER update_workspaces_timestamp
AFTER UPDATE ON workspaces
BEGIN
    UPDATE workspaces SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;

-- ================================================
-- 2. WORKSPACE MEMBERSHIPS TABLE
-- ================================================
-- Manages user access and roles within workspaces
CREATE TABLE IF NOT EXISTS workspace_memberships (
    id INTEGER PRIMARY KEY AUTOINCREMENT,

    -- Relationship
    workspace_id INTEGER NOT NULL,
    user_id INTEGER NOT NULL,

    -- Role-based access control
    -- OWNER: Full control (1 per workspace, transfers on ownership change)
    -- CO_OWNER: Can manage members and settings
    -- MEMBER_WRITE: Can add/edit transactions
    -- MEMBER_READ: Read-only access
    role TEXT NOT NULL CHECK(role IN ('OWNER', 'CO_OWNER', 'MEMBER_WRITE', 'MEMBER_READ')),

    -- Status tracking
    is_active BOOLEAN DEFAULT 1,
    joined_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,

    -- Prevent duplicate active memberships for same user-workspace pair
    UNIQUE(workspace_id, user_id, is_active)
);

-- Membership indexes for efficient querying
CREATE INDEX idx_workspace_memberships_workspace ON workspace_memberships(workspace_id);
CREATE INDEX idx_workspace_memberships_user ON workspace_memberships(user_id);
CREATE INDEX idx_workspace_memberships_role ON workspace_memberships(role);
CREATE INDEX idx_workspace_memberships_active ON workspace_memberships(is_active) WHERE is_active = 1;
CREATE INDEX idx_workspace_memberships_user_workspace ON workspace_memberships(user_id, workspace_id);

-- Trigger for memberships updated_at timestamp
CREATE TRIGGER update_workspace_memberships_timestamp
AFTER UPDATE ON workspace_memberships
BEGIN
    UPDATE workspace_memberships SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;

-- ================================================
-- 3. WORKSPACE INVITATIONS TABLE
-- ================================================
-- Token-based invitation system for workspace access
CREATE TABLE IF NOT EXISTS workspace_invitations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,

    -- Workspace relationship
    workspace_id INTEGER NOT NULL,

    -- Invitation token (URL-safe, 32-character random string)
    token TEXT NOT NULL UNIQUE,

    -- Role to be assigned when invitation is accepted
    -- Note: OWNER role cannot be assigned via invitations
    role TEXT NOT NULL CHECK(role IN ('CO_OWNER', 'MEMBER_WRITE', 'MEMBER_READ')),

    -- Invitation creator
    created_by_user_id INTEGER NOT NULL,

    -- Expiration and usage limits
    expires_at DATETIME NOT NULL,
    max_uses INTEGER,  -- NULL = unlimited uses
    current_uses INTEGER DEFAULT 0,

    -- Status tracking
    is_active BOOLEAN DEFAULT 1,
    revoked_at DATETIME,
    revoked_by_user_id INTEGER,

    -- Timestamps
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE,
    FOREIGN KEY (created_by_user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (revoked_by_user_id) REFERENCES users(id) ON DELETE SET NULL
);

-- Invitation indexes for token lookup and active invitations
CREATE UNIQUE INDEX idx_workspace_invitations_token ON workspace_invitations(token);
CREATE INDEX idx_workspace_invitations_workspace ON workspace_invitations(workspace_id);
CREATE INDEX idx_workspace_invitations_active ON workspace_invitations(is_active, expires_at) WHERE is_active = 1;

-- Trigger for invitations updated_at timestamp
CREATE TRIGGER update_workspace_invitations_timestamp
AFTER UPDATE ON workspace_invitations
BEGIN
    UPDATE workspace_invitations SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;

-- ================================================
-- 4. ALLOWANCE TRANSACTIONS TABLE
-- ================================================
-- Tracks which transactions are marked as "allowance" (용돈) for each user
CREATE TABLE IF NOT EXISTS allowance_transactions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,

    -- Relationship to transaction and user
    transaction_id INTEGER NOT NULL,
    user_id INTEGER NOT NULL,
    workspace_id INTEGER NOT NULL,

    -- Tracking information
    marked_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    notes TEXT,  -- Optional notes about why this is marked as allowance

    FOREIGN KEY (transaction_id) REFERENCES transactions(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE,

    -- Prevent duplicate allowance markings for same transaction-user-workspace combination
    UNIQUE(transaction_id, user_id, workspace_id)
);

-- Allowance transaction indexes for efficient querying
CREATE INDEX idx_allowance_transactions_transaction ON allowance_transactions(transaction_id);
CREATE INDEX idx_allowance_transactions_user_workspace ON allowance_transactions(user_id, workspace_id);
CREATE INDEX idx_allowance_transactions_workspace ON allowance_transactions(workspace_id);

-- ================================================
-- 5. MODIFY EXISTING TABLES - Add Workspace Columns
-- ================================================

-- Add workspace_id to transactions table
ALTER TABLE transactions ADD COLUMN workspace_id INTEGER REFERENCES workspaces(id) ON DELETE CASCADE;

-- Indexes for workspace-based transaction queries
CREATE INDEX idx_transactions_workspace ON transactions(workspace_id);
CREATE INDEX idx_transactions_workspace_date ON transactions(workspace_id, transaction_date DESC);

-- Add workspace tracking to processed_files table
ALTER TABLE processed_files ADD COLUMN workspace_id INTEGER REFERENCES workspaces(id) ON DELETE CASCADE;
ALTER TABLE processed_files ADD COLUMN uploaded_by_user_id INTEGER REFERENCES users(id) ON DELETE SET NULL;

-- Indexes for file tracking by workspace and uploader
CREATE INDEX idx_processed_files_workspace ON processed_files(workspace_id);
CREATE INDEX idx_processed_files_uploaded_by ON processed_files(uploaded_by_user_id);

-- ================================================
-- 6. DATA MIGRATION - Migrate Existing Data
-- ================================================

-- STEP 1: Create default workspace for each existing user
-- Each user gets their own personal workspace named "{User name}의 지출 관리"
INSERT INTO workspaces (name, description, created_by_user_id, created_at)
SELECT
    u.name || '의 지출 관리',  -- "{User name}'s expense tracker"
    '자동으로 생성된 기본 워크스페이스',  -- "Automatically generated default workspace"
    u.id,
    u.created_at
FROM users u;

-- STEP 2: Add OWNER membership for each user to their default workspace
-- Each user becomes the OWNER of their automatically created workspace
INSERT INTO workspace_memberships (workspace_id, user_id, role, joined_at)
SELECT
    w.id,
    u.id,
    'OWNER',
    u.created_at
FROM users u
JOIN workspaces w ON w.created_by_user_id = u.id;

-- STEP 3: Assign existing transactions to default workspaces
-- All existing transactions go to the first (oldest) workspace
-- This assumes single-user usage before workspace feature
UPDATE transactions
SET workspace_id = (
    SELECT w.id
    FROM workspaces w
    ORDER BY w.created_at ASC
    LIMIT 1
)
WHERE workspace_id IS NULL;

-- STEP 4: Assign existing processed files to default workspaces
-- All existing processed files go to the first (oldest) workspace
UPDATE processed_files
SET workspace_id = (
    SELECT w.id
    FROM workspaces w
    ORDER BY w.created_at ASC
    LIMIT 1
)
WHERE workspace_id IS NULL;

COMMIT;

-- ============================================
-- DOWN Migration (Rollback)
-- ============================================

-- To rollback, run these commands:
-- BEGIN TRANSACTION;
--
-- -- Remove indexes from modified tables
-- DROP INDEX IF EXISTS idx_processed_files_uploaded_by;
-- DROP INDEX IF EXISTS idx_processed_files_workspace;
-- DROP INDEX IF EXISTS idx_transactions_workspace_date;
-- DROP INDEX IF EXISTS idx_transactions_workspace;
--
-- -- Remove columns from existing tables (SQLite limitation workaround required)
-- -- SQLite does not support DROP COLUMN directly, requires table recreation
-- -- For production rollback, create new tables without workspace columns,
-- -- copy data, drop old tables, rename new tables
--
-- -- Drop allowance transactions
-- DROP INDEX IF EXISTS idx_allowance_transactions_workspace;
-- DROP INDEX IF EXISTS idx_allowance_transactions_user_workspace;
-- DROP INDEX IF EXISTS idx_allowance_transactions_transaction;
-- DROP TABLE IF EXISTS allowance_transactions;
--
-- -- Drop invitations
-- DROP TRIGGER IF EXISTS update_workspace_invitations_timestamp;
-- DROP INDEX IF EXISTS idx_workspace_invitations_active;
-- DROP INDEX IF EXISTS idx_workspace_invitations_workspace;
-- DROP INDEX IF EXISTS idx_workspace_invitations_token;
-- DROP TABLE IF EXISTS workspace_invitations;
--
-- -- Drop memberships
-- DROP TRIGGER IF EXISTS update_workspace_memberships_timestamp;
-- DROP INDEX IF EXISTS idx_workspace_memberships_user_workspace;
-- DROP INDEX IF EXISTS idx_workspace_memberships_active;
-- DROP INDEX IF EXISTS idx_workspace_memberships_role;
-- DROP INDEX IF EXISTS idx_workspace_memberships_user;
-- DROP INDEX IF EXISTS idx_workspace_memberships_workspace;
-- DROP TABLE IF EXISTS workspace_memberships;
--
-- -- Drop workspaces
-- DROP TRIGGER IF EXISTS update_workspaces_timestamp;
-- DROP INDEX IF EXISTS idx_workspaces_active;
-- DROP INDEX IF EXISTS idx_workspaces_created_by;
-- DROP TABLE IF EXISTS workspaces;
--
-- COMMIT;

-- ============================================
-- VERIFICATION QUERIES
-- ============================================

-- After running this migration, verify with these queries:

-- 1. Verify all 4 new tables exist
-- SELECT name FROM sqlite_master WHERE type='table' AND name IN ('workspaces', 'workspace_memberships', 'workspace_invitations', 'allowance_transactions');

-- 2. Verify all triggers exist
-- SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'update_workspace%';

-- 3. Verify all indexes exist
-- SELECT name FROM sqlite_master WHERE type='index' AND name LIKE '%workspace%';

-- 4. Verify data migration - check that all transactions have workspace_id
-- SELECT COUNT(*) as total_transactions, COUNT(workspace_id) as transactions_with_workspace FROM transactions;

-- 5. Verify data migration - check that all users have default workspace
-- SELECT u.id, u.name, w.id as workspace_id, w.name as workspace_name FROM users u LEFT JOIN workspaces w ON w.created_by_user_id = u.id;

-- 6. Verify data migration - check that all users have OWNER membership
-- SELECT u.id, u.name, wm.role, w.name as workspace_name FROM users u JOIN workspace_memberships wm ON wm.user_id = u.id JOIN workspaces w ON w.id = wm.workspace_id;

-- 7. Check foreign key integrity
-- PRAGMA foreign_key_check;

-- ============================================
-- PERFORMANCE NOTES
-- ============================================

-- Index Strategy:
-- - Covering indexes for common queries (user_id, workspace_id combinations)
-- - Partial indexes on active records (is_active = 1) to reduce index size
-- - Composite indexes ordered by query patterns (user_id first for user-centric queries)
--
-- Expected Impact:
-- - workspaces table: Low write volume, high read volume
-- - workspace_memberships: Low write volume, very high read volume (every request)
-- - workspace_invitations: Low volume overall, primarily reads for validation
-- - allowance_transactions: Medium write volume, high read volume for reporting
--
-- Query Performance:
-- - User workspace lookup: O(1) via idx_workspace_memberships_user_workspace
-- - Transaction filtering by workspace: O(log n) via idx_transactions_workspace_date
-- - Invitation token validation: O(1) via idx_workspace_invitations_token
-- - Allowance reporting: O(log n) via idx_allowance_transactions_user_workspace
--
-- Storage Considerations:
-- - 4 new tables: ~50 bytes/row average
-- - 2 new columns on existing tables: ~8 bytes each
-- - 13 new indexes: varies by data volume
-- - For 100k transactions: ~1-2 MB additional storage estimated
