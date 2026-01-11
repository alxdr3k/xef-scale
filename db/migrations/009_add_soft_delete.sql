-- Migration: 009_add_soft_delete.sql
-- Description: Add soft delete support for manual transaction management
-- Date: 2026-01-11
-- Author: Database Architect

BEGIN TRANSACTION;

-- ============================================
-- UP Migration
-- ============================================

-- Step 1: Add deleted_at column to transactions table
ALTER TABLE transactions ADD COLUMN deleted_at DATETIME DEFAULT NULL;

-- Step 2: Create partial index for active (non-deleted) transactions
-- This improves query performance by only indexing active records
CREATE INDEX idx_transactions_active ON transactions(deleted_at)
WHERE deleted_at IS NULL;

-- Step 3: Create partial index for deleted transactions (for audit queries)
CREATE INDEX idx_transactions_deleted ON transactions(deleted_at DESC)
WHERE deleted_at IS NOT NULL;

-- Step 4: Create view for editable transactions (manual only)
-- This simplifies queries that need to distinguish editable vs read-only
CREATE VIEW v_editable_transactions AS
SELECT
    t.*,
    c.name as category_name,
    i.name as institution_name
FROM transactions t
JOIN categories c ON t.category_id = c.id
JOIN financial_institutions i ON t.institution_id = i.id
WHERE t.file_id IS NULL
  AND t.deleted_at IS NULL;

-- Step 5: Create view for all active transactions (parsed + manual)
CREATE VIEW v_active_transactions AS
SELECT
    t.*,
    c.name as category_name,
    i.name as institution_name,
    CASE WHEN t.file_id IS NULL THEN 1 ELSE 0 END as is_editable
FROM transactions t
JOIN categories c ON t.category_id = c.id
JOIN financial_institutions i ON t.institution_id = i.id
WHERE t.deleted_at IS NULL;

COMMIT;

-- ============================================
-- DOWN Migration (Rollback)
-- ============================================

-- To rollback, run these commands:
-- BEGIN TRANSACTION;
-- DROP VIEW IF EXISTS v_active_transactions;
-- DROP VIEW IF EXISTS v_editable_transactions;
-- DROP INDEX IF EXISTS idx_transactions_deleted;
-- DROP INDEX IF EXISTS idx_transactions_active;
--
-- -- SQLite doesn't support DROP COLUMN, so we'd need to recreate table
-- CREATE TABLE transactions_rollback (
--     id INTEGER PRIMARY KEY AUTOINCREMENT,
--     transaction_year INTEGER NOT NULL,
--     transaction_month INTEGER NOT NULL,
--     transaction_date DATE NOT NULL,
--     category_id INTEGER NOT NULL,
--     institution_id INTEGER NOT NULL,
--     merchant_name TEXT NOT NULL,
--     amount INTEGER NOT NULL,
--     installment_months INTEGER,
--     installment_current INTEGER,
--     original_amount INTEGER,
--     raw_description TEXT,
--     notes TEXT,
--     is_recurring BOOLEAN DEFAULT 0,
--     file_id INTEGER,
--     row_number_in_file INTEGER,
--     created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
--     updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
--
--     FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE RESTRICT,
--     FOREIGN KEY (institution_id) REFERENCES financial_institutions(id) ON DELETE RESTRICT,
--     FOREIGN KEY (file_id) REFERENCES processed_files(id) ON DELETE SET NULL
-- );
--
-- INSERT INTO transactions_rollback SELECT
--     id, transaction_year, transaction_month, transaction_date,
--     category_id, institution_id, merchant_name, amount,
--     installment_months, installment_current, original_amount,
--     raw_description, notes, is_recurring, file_id, row_number_in_file,
--     created_at, updated_at
-- FROM transactions;
--
-- DROP TABLE transactions;
-- ALTER TABLE transactions_rollback RENAME TO transactions;
-- -- Recreate indexes from 004_add_file_tracking.sql
-- COMMIT;
