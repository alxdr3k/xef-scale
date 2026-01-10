-- Migration: 005_add_parsing_sessions.sql
-- Description: Add parsing session tracking and skipped transaction metadata
-- Date: 2026-01-10

BEGIN TRANSACTION;

-- ============================================
-- Create parsing_sessions table
-- ============================================
CREATE TABLE IF NOT EXISTS parsing_sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_id INTEGER NOT NULL,
    parser_type TEXT NOT NULL,

    -- Timing
    started_at DATETIME NOT NULL,
    completed_at DATETIME,

    -- Metrics
    total_rows_in_file INTEGER NOT NULL,
    rows_saved INTEGER NOT NULL DEFAULT 0,
    rows_skipped INTEGER NOT NULL DEFAULT 0,
    rows_duplicate INTEGER NOT NULL DEFAULT 0,

    -- Status tracking
    status TEXT NOT NULL CHECK(status IN ('pending', 'completed', 'failed')),
    error_message TEXT,

    -- Validation results
    validation_status TEXT CHECK(validation_status IN ('pass', 'warning', 'fail')),
    validation_notes TEXT,

    -- Timestamps
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (file_id) REFERENCES processed_files(id) ON DELETE CASCADE
);

-- Indexes for parsing_sessions
CREATE INDEX IF NOT EXISTS idx_parsing_sessions_file ON parsing_sessions(file_id);
CREATE INDEX IF NOT EXISTS idx_parsing_sessions_status ON parsing_sessions(status);
CREATE INDEX IF NOT EXISTS idx_parsing_sessions_started ON parsing_sessions(started_at DESC);
CREATE INDEX IF NOT EXISTS idx_parsing_sessions_validation ON parsing_sessions(validation_status);

-- Trigger for updated_at
CREATE TRIGGER IF NOT EXISTS update_parsing_sessions_timestamp
AFTER UPDATE ON parsing_sessions
BEGIN
    UPDATE parsing_sessions SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;

-- ============================================
-- Create skipped_transactions table
-- ============================================
CREATE TABLE IF NOT EXISTS skipped_transactions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id INTEGER NOT NULL,

    -- Row identification
    row_number INTEGER NOT NULL,

    -- Transaction metadata
    transaction_date TEXT,
    merchant_name TEXT,
    amount INTEGER,
    original_amount INTEGER,

    -- Skip reason
    skip_reason TEXT NOT NULL,
    skip_details TEXT,
    column_data TEXT,  -- JSON string

    -- Timestamps
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (session_id) REFERENCES parsing_sessions(id) ON DELETE CASCADE
);

-- Indexes for skipped_transactions
CREATE INDEX IF NOT EXISTS idx_skipped_transactions_session ON skipped_transactions(session_id);
CREATE INDEX IF NOT EXISTS idx_skipped_transactions_reason ON skipped_transactions(skip_reason);
CREATE INDEX IF NOT EXISTS idx_skipped_transactions_date ON skipped_transactions(transaction_date);

COMMIT;
