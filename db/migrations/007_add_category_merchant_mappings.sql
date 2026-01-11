-- Migration: 007_add_category_merchant_mappings.sql
-- Description: Create category_merchant_mappings table and populate with initial data from imported transactions
-- Date: 2026-01-11
-- Author: Database Architect
-- Task: cf51ab74 - DB Schema: Create category_merchant_mappings table and extract initial data
-- Estimated duration: 2-5 seconds on 1,177 imported transactions
-- Table lock: None (new table creation)
-- Expected mappings: ~715 unique category-merchant combinations

BEGIN TRANSACTION;

-- ============================================
-- UP Migration
-- ============================================

-- Category-merchant mappings table for machine learning and auto-categorization
-- This table stores merchant patterns that consistently map to specific categories
-- enabling automated transaction categorization based on historical data
CREATE TABLE IF NOT EXISTS category_merchant_mappings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,

    -- Foreign key to categories table
    category_id INTEGER NOT NULL,

    -- Merchant name pattern (exact merchant name or substring pattern)
    merchant_pattern TEXT NOT NULL,

    -- Match type determines how the pattern should be applied
    -- 'exact': Exact string match (case-insensitive)
    -- 'partial': Substring match for fuzzy matching
    match_type TEXT NOT NULL CHECK(match_type IN ('exact', 'partial')),

    -- Confidence score 0-100 indicating reliability of the mapping
    -- 100 = High confidence (manual or frequently occurring)
    -- Lower values indicate less certain automatic categorization
    confidence INTEGER DEFAULT 100 CHECK(confidence >= 0 AND confidence <= 100),

    -- Source of the mapping for audit trail
    -- 'imported_2024_2025': Extracted from historical imported data
    -- 'user_manual': User manually assigned
    -- 'ml_suggested': Machine learning suggested
    source TEXT DEFAULT 'imported',

    -- Audit timestamps
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,

    -- Enforce foreign key constraint with cascade delete
    -- If a category is deleted, all its mappings are also deleted
    FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE CASCADE,

    -- Prevent duplicate mappings for the same category-pattern-type combination
    UNIQUE(category_id, merchant_pattern, match_type)
);

-- Performance indexes for query optimization
-- Index on merchant_pattern for fast lookup during transaction categorization
CREATE INDEX idx_merchant_pattern ON category_merchant_mappings(merchant_pattern);

-- Index on category_id for category-based queries and reporting
CREATE INDEX idx_category_mappings ON category_merchant_mappings(category_id);

-- Index on match_type for filtering by matching strategy
CREATE INDEX idx_match_type ON category_merchant_mappings(match_type);

-- Composite index for the most common query pattern (pattern + type lookup)
CREATE INDEX idx_merchant_lookup ON category_merchant_mappings(merchant_pattern, match_type);

-- Trigger for updated_at timestamp
CREATE TRIGGER update_category_merchant_mappings_timestamp
AFTER UPDATE ON category_merchant_mappings
BEGIN
    UPDATE category_merchant_mappings SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;

-- ============================================
-- Populate with initial data from imported transactions
-- ============================================

-- Extract exact merchant mappings from imported transactions (institution_id = 38)
-- Only include merchants that have been consistently categorized (not as '기타')
-- This creates a training dataset for future auto-categorization

INSERT INTO category_merchant_mappings (category_id, merchant_pattern, match_type, confidence, source)
SELECT
    t.category_id,
    t.merchant_name as merchant_pattern,
    'exact' as match_type,
    100 as confidence,
    'imported_2024_2025' as source
FROM transactions t
WHERE t.institution_id = 38
    AND t.category_id <> (SELECT id FROM categories WHERE name = '기타')
GROUP BY t.category_id, t.merchant_name
HAVING COUNT(*) >= 1  -- At least 1 occurrence (can be adjusted for higher confidence)
ON CONFLICT (category_id, merchant_pattern, match_type) DO NOTHING;

-- Track migration execution
INSERT INTO _migrations (filename, executed_at)
VALUES ('007_add_category_merchant_mappings.sql', CURRENT_TIMESTAMP);

COMMIT;

-- ============================================
-- Validation Queries (Run after migration)
-- ============================================

-- Check table created successfully
-- SELECT name FROM sqlite_master WHERE type='table' AND name='category_merchant_mappings';

-- Verify data insertion count
-- SELECT COUNT(*) as total_mappings FROM category_merchant_mappings;

-- View sample mappings with category names
-- SELECT
--     c.name as category,
--     cm.merchant_pattern,
--     cm.match_type,
--     cm.confidence,
--     cm.source
-- FROM category_merchant_mappings cm
-- JOIN categories c ON cm.category_id = c.id
-- LIMIT 20;

-- Check distribution of mappings by category
-- SELECT
--     c.name as category,
--     COUNT(*) as mapping_count
-- FROM category_merchant_mappings cm
-- JOIN categories c ON cm.category_id = c.id
-- GROUP BY c.name
-- ORDER BY mapping_count DESC;

-- ============================================
-- DOWN Migration (Rollback)
-- ============================================

-- To rollback, run these commands:
-- BEGIN TRANSACTION;
-- DROP TRIGGER IF EXISTS update_category_merchant_mappings_timestamp;
-- DROP INDEX IF EXISTS idx_merchant_lookup;
-- DROP INDEX IF EXISTS idx_match_type;
-- DROP INDEX IF EXISTS idx_category_mappings;
-- DROP INDEX IF EXISTS idx_merchant_pattern;
-- DROP TABLE IF EXISTS category_merchant_mappings;
-- DELETE FROM _migrations WHERE filename = '007_add_category_merchant_mappings.sql';
-- COMMIT;
