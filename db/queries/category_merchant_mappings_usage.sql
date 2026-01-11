-- ============================================
-- Category-Merchant Mappings Usage Examples
-- ============================================
-- Table: category_merchant_mappings
-- Purpose: Store merchant patterns for automated transaction categorization
-- Migration: 007_add_category_merchant_mappings.sql

-- ============================================
-- 1. Lookup Category by Merchant Name (Exact Match)
-- ============================================
-- Use case: Auto-categorize a new transaction with known merchant
SELECT
    cm.category_id,
    c.name as category_name,
    cm.confidence
FROM category_merchant_mappings cm
JOIN categories c ON cm.category_id = c.id
WHERE cm.merchant_pattern = '쿠팡'
    AND cm.match_type = 'exact'
LIMIT 1;

-- ============================================
-- 2. Fuzzy Merchant Lookup (Partial Match)
-- ============================================
-- Use case: Find category for merchant with slight variations
SELECT
    cm.category_id,
    c.name as category_name,
    cm.merchant_pattern,
    cm.confidence
FROM category_merchant_mappings cm
JOIN categories c ON cm.category_id = c.id
WHERE cm.merchant_pattern LIKE '%스타벅스%'
ORDER BY cm.confidence DESC, LENGTH(cm.merchant_pattern) ASC
LIMIT 5;

-- ============================================
-- 3. Get All Merchants for a Category
-- ============================================
-- Use case: Review all merchants mapped to a specific category
SELECT
    cm.merchant_pattern,
    cm.match_type,
    cm.confidence,
    cm.source,
    COUNT(t.id) as transaction_count
FROM category_merchant_mappings cm
JOIN categories c ON cm.category_id = c.id
LEFT JOIN transactions t ON t.merchant_name = cm.merchant_pattern AND t.category_id = cm.category_id
WHERE c.name = '식비'
GROUP BY cm.merchant_pattern, cm.match_type, cm.confidence, cm.source
ORDER BY transaction_count DESC;

-- ============================================
-- 4. Add New Mapping (User Manual)
-- ============================================
-- Use case: User manually assigns a merchant to a category
INSERT INTO category_merchant_mappings (category_id, merchant_pattern, match_type, confidence, source)
VALUES (
    (SELECT id FROM categories WHERE name = '카페/간식'),
    '블루보틀',
    'exact',
    100,
    'user_manual'
)
ON CONFLICT (category_id, merchant_pattern, match_type) DO UPDATE SET
    confidence = excluded.confidence,
    source = excluded.source,
    updated_at = CURRENT_TIMESTAMP;

-- ============================================
-- 5. Batch Add Mappings from Transactions
-- ============================================
-- Use case: Extract patterns from newly imported transactions
INSERT INTO category_merchant_mappings (category_id, merchant_pattern, match_type, confidence, source)
SELECT
    t.category_id,
    t.merchant_name,
    'exact' as match_type,
    CASE
        WHEN COUNT(*) >= 5 THEN 100
        WHEN COUNT(*) >= 3 THEN 90
        ELSE 80
    END as confidence,
    'batch_import' as source
FROM transactions t
WHERE t.institution_id = 38
    AND t.category_id != (SELECT id FROM categories WHERE name = '기타')
    AND t.merchant_name NOT IN (SELECT merchant_pattern FROM category_merchant_mappings)
GROUP BY t.category_id, t.merchant_name
HAVING COUNT(*) >= 2  -- At least 2 occurrences
ON CONFLICT (category_id, merchant_pattern, match_type) DO NOTHING;

-- ============================================
-- 6. Find Ambiguous Merchants (Multiple Categories)
-- ============================================
-- Use case: Identify merchants that appear in multiple categories
SELECT
    merchant_pattern,
    GROUP_CONCAT(category_name, ', ') as categories,
    COUNT(DISTINCT category_id) as category_count,
    total_transactions
FROM (
    SELECT
        cm.merchant_pattern,
        cm.category_id,
        c.name as category_name,
        COUNT(t.id) as total_transactions
    FROM category_merchant_mappings cm
    JOIN categories c ON cm.category_id = c.id
    LEFT JOIN transactions t ON t.merchant_name = cm.merchant_pattern
    GROUP BY cm.merchant_pattern, cm.category_id
)
GROUP BY merchant_pattern
HAVING category_count > 1
ORDER BY total_transactions DESC;

-- ============================================
-- 7. Update Confidence Score
-- ============================================
-- Use case: Adjust confidence based on user feedback or ML model
UPDATE category_merchant_mappings
SET confidence = 95
WHERE merchant_pattern = '쿠팡'
    AND category_id = (SELECT id FROM categories WHERE name = '편의점/마트/잡화');

-- ============================================
-- 8. Category Distribution Statistics
-- ============================================
-- Use case: Analyze category coverage for reporting
SELECT
    c.name as category,
    COUNT(cm.id) as mapping_count,
    COUNT(DISTINCT t.merchant_name) as actual_merchant_count,
    ROUND(COUNT(cm.id) * 100.0 / (SELECT COUNT(*) FROM category_merchant_mappings), 1) as coverage_pct
FROM categories c
LEFT JOIN category_merchant_mappings cm ON cm.category_id = c.id
LEFT JOIN transactions t ON t.category_id = c.id
GROUP BY c.name
ORDER BY mapping_count DESC;

-- ============================================
-- 9. Find Unmapped Merchants in Transactions
-- ============================================
-- Use case: Identify merchants that need categorization mapping
SELECT
    t.merchant_name,
    c.name as current_category,
    COUNT(*) as transaction_count,
    SUM(t.amount) as total_amount
FROM transactions t
JOIN categories c ON t.category_id = c.id
WHERE t.merchant_name NOT IN (
    SELECT merchant_pattern
    FROM category_merchant_mappings
)
AND t.institution_id = 38
GROUP BY t.merchant_name, c.name
ORDER BY transaction_count DESC
LIMIT 20;

-- ============================================
-- 10. Auto-Categorize Uncategorized Transactions
-- ============================================
-- Use case: Apply mappings to transactions marked as '기타'
UPDATE transactions
SET category_id = (
    SELECT cm.category_id
    FROM category_merchant_mappings cm
    WHERE cm.merchant_pattern = transactions.merchant_name
        AND cm.match_type = 'exact'
    ORDER BY cm.confidence DESC
    LIMIT 1
)
WHERE category_id = (SELECT id FROM categories WHERE name = '기타')
    AND merchant_name IN (
        SELECT merchant_pattern
        FROM category_merchant_mappings
        WHERE match_type = 'exact'
    );

-- ============================================
-- 11. Clean Up Low-Confidence Mappings
-- ============================================
-- Use case: Remove mappings that are rarely used or low confidence
DELETE FROM category_merchant_mappings
WHERE confidence < 70
    AND id NOT IN (
        SELECT DISTINCT cm.id
        FROM category_merchant_mappings cm
        JOIN transactions t ON t.merchant_name = cm.merchant_pattern AND t.category_id = cm.category_id
        WHERE t.created_at > datetime('now', '-3 months')
    );

-- ============================================
-- 12. Validate Mapping Accuracy
-- ============================================
-- Use case: Check if mappings match actual transaction categorizations
SELECT
    cm.merchant_pattern,
    c_mapping.name as mapped_category,
    c_actual.name as actual_category,
    COUNT(*) as mismatch_count
FROM category_merchant_mappings cm
JOIN categories c_mapping ON cm.category_id = c_mapping.id
JOIN transactions t ON t.merchant_name = cm.merchant_pattern
JOIN categories c_actual ON t.category_id = c_actual.id
WHERE cm.category_id != t.category_id
GROUP BY cm.merchant_pattern, c_mapping.name, c_actual.name
ORDER BY mismatch_count DESC
LIMIT 20;
