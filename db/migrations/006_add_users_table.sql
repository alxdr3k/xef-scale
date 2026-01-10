-- Migration: 006_add_users_table.sql
-- Description: Create users table for Google OAuth authentication
-- Date: 2026-01-11
-- Author: Database Architect
-- Task: d869c9c9 - Phase1-DB users table schema

BEGIN TRANSACTION;

-- ============================================
-- UP Migration
-- ============================================

-- Users table for Google OAuth authentication
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,

    -- Basic profile information
    email TEXT NOT NULL UNIQUE,
    google_id TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    profile_picture_url TEXT,

    -- OAuth tokens (stored encrypted by application)
    -- SECURITY: These fields contain encrypted token values
    -- Application layer must handle encryption/decryption using Fernet or similar
    access_token TEXT,
    refresh_token TEXT,
    token_expires_at DATETIME,

    -- Account status and metadata
    is_active BOOLEAN DEFAULT 1,
    last_login_at DATETIME,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for authentication and lookup performance
CREATE UNIQUE INDEX idx_users_email ON users(email);
CREATE UNIQUE INDEX idx_users_google_id ON users(google_id);
CREATE INDEX idx_users_active ON users(is_active) WHERE is_active = 1;
CREATE INDEX idx_users_last_login ON users(last_login_at DESC);

-- Trigger for updated_at timestamp
CREATE TRIGGER update_users_timestamp
AFTER UPDATE ON users
BEGIN
    UPDATE users SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;

COMMIT;

-- ============================================
-- DOWN Migration (Rollback)
-- ============================================

-- To rollback, run these commands:
-- DROP TRIGGER IF EXISTS update_users_timestamp;
-- DROP TABLE IF EXISTS users;
