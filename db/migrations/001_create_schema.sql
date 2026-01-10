-- Migration: 001_create_schema.sql
-- Description: Initial schema creation for expense tracker
-- Date: 2026-01-10
-- Author: Database Architect

BEGIN TRANSACTION;

-- ============================================
-- UP Migration
-- ============================================

-- Categories table
CREATE TABLE IF NOT EXISTS categories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE,
    parent_id INTEGER,
    description TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (parent_id) REFERENCES categories(id) ON DELETE SET NULL
);

CREATE INDEX idx_categories_name ON categories(name);
CREATE INDEX idx_categories_parent ON categories(parent_id);

-- Financial institutions table
CREATE TABLE IF NOT EXISTS financial_institutions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE,
    institution_type TEXT NOT NULL CHECK(institution_type IN ('CARD', 'BANK', 'PAY')),
    display_name TEXT,
    is_active BOOLEAN DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_institutions_name ON financial_institutions(name);
CREATE INDEX idx_institutions_type ON financial_institutions(institution_type);
CREATE INDEX idx_institutions_active ON financial_institutions(is_active);

-- Transactions table
CREATE TABLE IF NOT EXISTS transactions (
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
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE RESTRICT,
    FOREIGN KEY (institution_id) REFERENCES financial_institutions(id) ON DELETE RESTRICT,

    UNIQUE(transaction_date, institution_id, merchant_name, amount, installment_current)
);

-- Transaction indexes
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

-- Triggers for updated_at timestamp
CREATE TRIGGER update_categories_timestamp
AFTER UPDATE ON categories
BEGIN
    UPDATE categories SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;

CREATE TRIGGER update_institutions_timestamp
AFTER UPDATE ON financial_institutions
BEGIN
    UPDATE financial_institutions SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;

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
-- DROP TRIGGER IF EXISTS update_transactions_timestamp;
-- DROP TRIGGER IF EXISTS update_institutions_timestamp;
-- DROP TRIGGER IF EXISTS update_categories_timestamp;
-- DROP TABLE IF EXISTS transactions;
-- DROP TABLE IF EXISTS financial_institutions;
-- DROP TABLE IF EXISTS categories;
