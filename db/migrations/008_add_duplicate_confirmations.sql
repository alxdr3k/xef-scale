-- Migration: 008_add_duplicate_confirmations.sql
-- Description: Create duplicate_transaction_confirmations table for tracking potential duplicates requiring user confirmation
-- Date: 2026-01-11
-- Author: Database Architect
-- Task: febf5c3d - Phase1-DB duplicate confirmations schema

BEGIN TRANSACTION;

-- ============================================
-- UP Migration
-- ============================================

-- Duplicate transaction confirmations table
-- Tracks potential duplicate transactions that require user review before insertion
CREATE TABLE IF NOT EXISTS duplicate_transaction_confirmations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,

    -- Session context
    session_id INTEGER NOT NULL,

    -- Transaction data
    -- JSON serialized transaction data that hasn't been inserted yet
    new_transaction_data TEXT NOT NULL,
    new_transaction_index INTEGER NOT NULL,
    existing_transaction_id INTEGER NOT NULL,

    -- Duplicate detection metadata
    confidence_score INTEGER NOT NULL CHECK(confidence_score >= 0 AND confidence_score <= 100),
    -- JSON array of matched field names: ['date', 'amount', 'merchant']
    match_fields TEXT NOT NULL,
    difference_summary TEXT,

    -- User decision tracking
    status TEXT NOT NULL CHECK(status IN ('pending', 'confirmed_insert', 'confirmed_skip', 'confirmed_merge', 'expired')),
    user_action TEXT CHECK(user_action IN ('insert', 'skip', 'merge')),
    user_id TEXT,
    decided_at DATETIME,

    -- Timestamps and lifecycle
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    expires_at DATETIME,  -- 30 days from creation for automatic cleanup

    -- Foreign keys
    FOREIGN KEY (session_id) REFERENCES parsing_sessions(id) ON DELETE CASCADE,
    FOREIGN KEY (existing_transaction_id) REFERENCES transactions(id) ON DELETE CASCADE
);

-- Indexes for query performance
CREATE INDEX idx_duplicate_confirmations_session ON duplicate_transaction_confirmations(session_id);
CREATE INDEX idx_duplicate_confirmations_status ON duplicate_transaction_confirmations(status);
CREATE INDEX idx_duplicate_confirmations_existing ON duplicate_transaction_confirmations(existing_transaction_id);

-- Partial index for pending confirmations expiration queries
CREATE INDEX idx_duplicate_confirmations_expires ON duplicate_transaction_confirmations(expires_at)
WHERE status = 'pending';

COMMIT;

-- ============================================
-- DOWN Migration (Rollback)
-- ============================================

-- To rollback, run these commands:
-- DROP INDEX IF EXISTS idx_duplicate_confirmations_expires;
-- DROP INDEX IF EXISTS idx_duplicate_confirmations_existing;
-- DROP INDEX IF EXISTS idx_duplicate_confirmations_status;
-- DROP INDEX IF EXISTS idx_duplicate_confirmations_session;
-- DROP TABLE IF EXISTS duplicate_transaction_confirmations;
