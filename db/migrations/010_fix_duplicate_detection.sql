-- Migration: 010_fix_duplicate_detection.sql
-- Description: Fix duplicate transaction detection by handling NULL installment_current
-- Date: 2026-01-11
-- Author: Backend Architect
-- Issue: SQLite UNIQUE constraints don't match NULL values, causing duplicate transactions
--        with NULL installment_current to not be detected as duplicates

BEGIN TRANSACTION;

-- ============================================
-- Problem Analysis
-- ============================================
-- The existing UNIQUE constraint:
--   UNIQUE(transaction_date, institution_id, merchant_name, amount, installment_current)
--
-- In SQLite, NULL != NULL, so two transactions with:
--   - Same date, institution, merchant, amount
--   - Both having installment_current = NULL
-- Are NOT considered duplicates!
--
-- Solution: Use COALESCE to treat NULL as 0 in the constraint via partial index

-- ============================================
-- UP Migration
-- ============================================

-- Step 1: Drop views that depend on transactions table (from migration 009)
DROP VIEW IF EXISTS v_active_transactions;
DROP VIEW IF EXISTS v_editable_transactions;

-- Step 2: Drop the existing UNIQUE constraint
-- SQLite doesn't support DROP CONSTRAINT, so we need to recreate the table

-- Create temporary table with new schema
CREATE TABLE transactions_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    transaction_year INTEGER NOT NULL,
    transaction_month INTEGER NOT NULL,
    transaction_date DATE NOT NULL,
    category_id INTEGER NOT NULL,
    institution_id INTEGER NOT NULL,
    merchant_name TEXT NOT NULL,
    amount INTEGER NOT NULL,
    installment_months INTEGER,
    installment_current INTEGER,
    original_amount INTEGER,
    raw_description TEXT,
    notes TEXT,
    is_recurring BOOLEAN DEFAULT 0,
    file_id INTEGER,
    row_number_in_file INTEGER,
    deleted_at DATETIME,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE RESTRICT,
    FOREIGN KEY (institution_id) REFERENCES financial_institutions(id) ON DELETE RESTRICT,
    FOREIGN KEY (file_id) REFERENCES processed_files(id) ON DELETE SET NULL
);

-- Copy all data from old table to new table
INSERT INTO transactions_new
SELECT * FROM transactions;

-- Drop old table
DROP TABLE transactions;

-- Rename new table to original name
ALTER TABLE transactions_new RENAME TO transactions;

-- Step 3: Create proper UNIQUE constraint that handles NULLs
-- We create a unique index using COALESCE to treat NULL as 0
CREATE UNIQUE INDEX idx_transactions_duplicate_detection
ON transactions(
    transaction_date,
    institution_id,
    merchant_name,
    amount,
    COALESCE(installment_current, 0)
)
WHERE deleted_at IS NULL;

-- Step 4: Recreate all indexes
CREATE INDEX idx_transactions_year_month ON transactions(transaction_year, transaction_month);
CREATE INDEX idx_transactions_date ON transactions(transaction_date DESC);
CREATE INDEX idx_transactions_category_year ON transactions(category_id, transaction_year, transaction_month);
CREATE INDEX idx_transactions_institution_year ON transactions(institution_id, transaction_year, transaction_month);
CREATE INDEX idx_transactions_analysis ON transactions(transaction_year, transaction_month, category_id, institution_id);
CREATE INDEX idx_transactions_merchant ON transactions(merchant_name COLLATE NOCASE);
CREATE INDEX idx_transactions_installment ON transactions(installment_months, installment_current)
WHERE installment_months IS NOT NULL;
CREATE INDEX idx_transactions_recurring ON transactions(is_recurring, category_id)
WHERE is_recurring = 1;
CREATE INDEX idx_transactions_file ON transactions(file_id);
CREATE INDEX idx_transactions_deleted ON transactions(deleted_at);

-- Step 5: Recreate trigger
CREATE TRIGGER update_transactions_timestamp
AFTER UPDATE ON transactions
BEGIN
    UPDATE transactions SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;

-- Step 6: Recreate views from migration 009 (they depend on transactions table)
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

-- To rollback:
-- 1. Drop the unique index: DROP INDEX idx_transactions_duplicate_detection;
-- 2. Recreate table with old UNIQUE constraint
-- 3. Restore data

-- Notes:
-- - This migration fixes the duplicate detection bug
-- - The UNIQUE index with COALESCE treats NULL installment_current as 0
-- - This ensures proper duplicate detection for manual transactions
-- - The WHERE deleted_at IS NULL clause ensures deleted transactions don't block new ones
