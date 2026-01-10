-- Migration: 004_add_file_tracking.sql
-- Description: Add file tracking to prevent duplicate file processing
-- Date: 2026-01-10
-- Author: Database Architect

BEGIN TRANSACTION;

-- ============================================
-- UP Migration
-- ============================================

-- Step 1: Create processed_files table for file deduplication
CREATE TABLE IF NOT EXISTS processed_files (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_name TEXT NOT NULL,
    file_path TEXT NOT NULL,
    file_hash TEXT NOT NULL UNIQUE,  -- SHA256 hash for duplicate detection
    file_size INTEGER NOT NULL,
    institution_id INTEGER NOT NULL,
    processed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    archive_path TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (institution_id) REFERENCES financial_institutions(id) ON DELETE RESTRICT
);

-- Indexes for processed_files
CREATE UNIQUE INDEX idx_processed_files_hash ON processed_files(file_hash);
CREATE INDEX idx_processed_files_institution ON processed_files(institution_id);
CREATE INDEX idx_processed_files_processed_at ON processed_files(processed_at DESC);

-- Trigger for updated_at timestamp
CREATE TRIGGER update_processed_files_timestamp
AFTER UPDATE ON processed_files
BEGIN
    UPDATE processed_files SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;


-- Step 2: Recreate transactions table with file tracking columns
-- SQLite does not support ALTER TABLE to modify constraints, so we must recreate the table

-- Create new transactions table with file tracking columns
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
    file_id INTEGER,  -- NEW: Link to processed_files table
    row_number_in_file INTEGER,  -- NEW: Row number within the source file
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE RESTRICT,
    FOREIGN KEY (institution_id) REFERENCES financial_institutions(id) ON DELETE RESTRICT,
    FOREIGN KEY (file_id) REFERENCES processed_files(id) ON DELETE SET NULL
);

-- Copy all existing data from old table to new table
-- Existing 168 transactions will have NULL file_id and row_number_in_file
INSERT INTO transactions_new (
    id,
    transaction_year,
    transaction_month,
    transaction_date,
    category_id,
    institution_id,
    merchant_name,
    amount,
    installment_months,
    installment_current,
    original_amount,
    raw_description,
    notes,
    is_recurring,
    file_id,
    row_number_in_file,
    created_at,
    updated_at
)
SELECT
    id,
    transaction_year,
    transaction_month,
    transaction_date,
    category_id,
    institution_id,
    merchant_name,
    amount,
    installment_months,
    installment_current,
    original_amount,
    raw_description,
    notes,
    is_recurring,
    NULL as file_id,  -- Existing transactions have no file tracking
    NULL as row_number_in_file,
    created_at,
    updated_at
FROM transactions;

-- Drop old table
DROP TABLE transactions;

-- Rename new table to original name
ALTER TABLE transactions_new RENAME TO transactions;

-- Recreate all indexes from original schema
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

-- New index for file tracking queries
CREATE INDEX idx_transactions_file ON transactions(file_id, row_number_in_file)
WHERE file_id IS NOT NULL;

-- New UNIQUE constraint: Within a file, each row number must be unique (partial unique index)
CREATE UNIQUE INDEX idx_transactions_file_unique ON transactions(file_id, row_number_in_file)
WHERE file_id IS NOT NULL;

-- Old UNIQUE constraint: For backward compatibility with NULL file_id (existing 168 transactions)
CREATE UNIQUE INDEX idx_transactions_legacy_unique ON transactions(transaction_date, institution_id, merchant_name, amount, COALESCE(installment_current, -1))
WHERE file_id IS NULL;

-- Recreate trigger for updated_at timestamp
CREATE TRIGGER update_transactions_timestamp
AFTER UPDATE ON transactions
BEGIN
    UPDATE transactions SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;

COMMIT;

-- ============================================
-- DOWN Migration (Rollback)
-- ============================================

-- To rollback, run these commands:
-- BEGIN TRANSACTION;
--
-- -- Drop new trigger
-- DROP TRIGGER IF EXISTS update_processed_files_timestamp;
--
-- -- Drop processed_files table
-- DROP TABLE IF EXISTS processed_files;
--
-- -- Recreate original transactions table (without file_id columns)
-- CREATE TABLE transactions_old (
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
--     created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
--     updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
--
--     FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE RESTRICT,
--     FOREIGN KEY (institution_id) REFERENCES financial_institutions(id) ON DELETE RESTRICT,
--
--     UNIQUE(transaction_date, institution_id, merchant_name, amount, installment_current)
-- );
--
-- -- Copy data back (excluding file tracking columns)
-- INSERT INTO transactions_old SELECT
--     id, transaction_year, transaction_month, transaction_date,
--     category_id, institution_id, merchant_name, amount,
--     installment_months, installment_current, original_amount,
--     raw_description, notes, is_recurring, created_at, updated_at
-- FROM transactions;
--
-- DROP TABLE transactions;
-- ALTER TABLE transactions_old RENAME TO transactions;
--
-- -- Recreate original indexes and triggers (see 001_create_schema.sql)
--
-- COMMIT;
