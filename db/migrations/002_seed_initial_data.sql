-- Migration: 002_seed_initial_data.sql
-- Description: Insert default categories and financial institutions
-- Date: 2026-01-10
-- Author: Database Architect

BEGIN TRANSACTION;

-- ============================================
-- UP Migration: Seed Data
-- ============================================

-- Insert default categories
INSERT INTO categories (name, parent_id, description) VALUES
    ('식비', NULL, '음식점, 식자재 구입'),
    ('편의점/마트/잡화', NULL, '편의점, 마트, 생필품'),
    ('교통/자동차', NULL, '대중교통, 주유, 주차'),
    ('주거/통신', NULL, '월세, 관리비, 인터넷, 통신비'),
    ('보험', NULL, '건강보험, 자동차보험 등'),
    ('의료/건강', NULL, '병원, 약국, 건강용품'),
    ('쇼핑', NULL, '의류, 전자제품 등'),
    ('여가/문화', NULL, '영화, 공연, 취미'),
    ('구독서비스', NULL, 'Netflix, Spotify 등'),
    ('기타', NULL, '분류되지 않은 지출');

-- Insert sub-categories (example)
INSERT INTO categories (name, parent_id, description)
SELECT '외식', id, '레스토랑, 카페' FROM categories WHERE name = '식비';

INSERT INTO categories (name, parent_id, description)
SELECT '배달', id, '배달음식' FROM categories WHERE name = '식비';

-- Insert default financial institutions
INSERT INTO financial_institutions (name, institution_type, display_name, is_active) VALUES
    ('신한카드', 'CARD', '신한카드', 1),
    ('하나카드', 'CARD', '하나카드', 1),
    ('토스뱅크', 'BANK', '토스뱅크', 1),
    ('토스페이', 'PAY', '토스페이', 1),
    ('카카오뱅크', 'BANK', '카카오뱅크', 1),
    ('카카오페이', 'PAY', '카카오페이', 1);

COMMIT;

-- ============================================
-- DOWN Migration (Rollback)
-- ============================================

-- To rollback:
-- DELETE FROM financial_institutions WHERE name IN ('신한카드', '하나카드', '토스뱅크', '토스페이', '카카오뱅크', '카카오페이');
-- DELETE FROM categories;
