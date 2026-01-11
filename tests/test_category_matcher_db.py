"""
Unit tests for CategoryMatcher with database integration.
Tests both database-driven mode and legacy keyword-only mode.
"""

import pytest
import sqlite3
from src.category_matcher import CategoryMatcher
from src.db.repository import CategoryRepository, CategoryMerchantMappingRepository


class TestCategoryMatcherLegacyMode:
    """Test CategoryMatcher in legacy mode (without database repositories)."""

    def test_legacy_mode_keyword_match(self):
        """Test keyword matching in legacy mode."""
        matcher = CategoryMatcher()

        # Test keyword matches from config.py
        assert matcher.get_category('식당 테스트') == '식비'
        assert matcher.get_category('음식 가게') == '식비'
        assert matcher.get_category('GS주유소') == '교통'
        assert matcher.get_category('KT통신') == '통신'

    def test_legacy_mode_no_match(self):
        """Test default category when no keyword match."""
        matcher = CategoryMatcher()
        assert matcher.get_category('알수없는가게') == '기타'

    def test_legacy_mode_empty_merchant(self):
        """Test empty merchant name handling."""
        matcher = CategoryMatcher()
        assert matcher.get_category('') == '기타'
        assert matcher.get_category('   ') == '기타'


class TestCategoryMatcherDatabaseMode:
    """Test CategoryMatcher in database mode (with repositories)."""

    @pytest.fixture
    def db_conn(self):
        """Create in-memory database for testing."""
        conn = sqlite3.connect(':memory:')
        conn.row_factory = sqlite3.Row

        # Create tables
        conn.execute('''
            CREATE TABLE categories (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL UNIQUE,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')

        conn.execute('''
            CREATE TABLE category_merchant_mappings (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                category_id INTEGER NOT NULL,
                merchant_pattern TEXT NOT NULL,
                match_type TEXT NOT NULL CHECK(match_type IN ('exact', 'partial')),
                confidence INTEGER NOT NULL DEFAULT 100 CHECK(confidence >= 0 AND confidence <= 100),
                source TEXT NOT NULL DEFAULT 'manual',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE(category_id, merchant_pattern, match_type),
                FOREIGN KEY (category_id) REFERENCES categories(id)
            )
        ''')

        # Insert test categories
        conn.execute("INSERT INTO categories (id, name) VALUES (1, '카페/간식')")
        conn.execute("INSERT INTO categories (id, name) VALUES (2, '식비')")
        conn.execute("INSERT INTO categories (id, name) VALUES (3, '교통')")
        conn.commit()

        # Insert test mappings
        conn.execute(
            "INSERT INTO category_merchant_mappings (category_id, merchant_pattern, match_type, confidence, source) "
            "VALUES (1, '스타벅스', 'exact', 100, 'test')"
        )
        conn.execute(
            "INSERT INTO category_merchant_mappings (category_id, merchant_pattern, match_type, confidence, source) "
            "VALUES (1, '블루보틀', 'exact', 100, 'test')"
        )
        conn.execute(
            "INSERT INTO category_merchant_mappings (category_id, merchant_pattern, match_type, confidence, source) "
            "VALUES (2, '맥도날드', 'partial', 95, 'test')"
        )
        conn.commit()

        yield conn
        conn.close()

    def test_database_mode_exact_match(self, db_conn):
        """Test exact match in database mode."""
        category_repo = CategoryRepository(db_conn)
        mapping_repo = CategoryMerchantMappingRepository(db_conn)
        matcher = CategoryMatcher(mapping_repo=mapping_repo, category_repo=category_repo)

        # Exact match should work
        assert matcher.get_category('스타벅스') == '카페/간식'
        assert matcher.get_category('블루보틀') == '카페/간식'

    def test_database_mode_partial_match(self, db_conn):
        """Test partial match in database mode."""
        category_repo = CategoryRepository(db_conn)
        mapping_repo = CategoryMerchantMappingRepository(db_conn)
        matcher = CategoryMatcher(mapping_repo=mapping_repo, category_repo=category_repo)

        # Partial match should work
        assert matcher.get_category('맥도날드 강남점') == '식비'
        assert matcher.get_category('강남 맥도날드') == '식비'

    def test_database_mode_fallback_to_keywords(self, db_conn):
        """Test fallback to keyword rules when no database match."""
        category_repo = CategoryRepository(db_conn)
        mapping_repo = CategoryMerchantMappingRepository(db_conn)
        matcher = CategoryMatcher(mapping_repo=mapping_repo, category_repo=category_repo)

        # Not in database, should fall back to keyword rules from config
        assert matcher.get_category('식당 테스트') == '식비'
        assert matcher.get_category('주유소') == '교통'

    def test_database_mode_default_category(self, db_conn):
        """Test default category when no match in database or keywords."""
        category_repo = CategoryRepository(db_conn)
        mapping_repo = CategoryMerchantMappingRepository(db_conn)
        matcher = CategoryMatcher(mapping_repo=mapping_repo, category_repo=category_repo)

        # No match anywhere, should return default
        assert matcher.get_category('알수없는가게') == '기타'

    def test_database_mode_empty_merchant(self, db_conn):
        """Test empty merchant name handling in database mode."""
        category_repo = CategoryRepository(db_conn)
        mapping_repo = CategoryMerchantMappingRepository(db_conn)
        matcher = CategoryMatcher(mapping_repo=mapping_repo, category_repo=category_repo)

        assert matcher.get_category('') == '기타'
        assert matcher.get_category('   ') == '기타'

    def test_database_mode_priority(self, db_conn):
        """Test that database match has priority over keyword rules."""
        category_repo = CategoryRepository(db_conn)
        mapping_repo = CategoryMerchantMappingRepository(db_conn)
        matcher = CategoryMatcher(mapping_repo=mapping_repo, category_repo=category_repo)

        # Add a mapping that conflicts with keyword rule
        # "음식" is a keyword for "식비" in config, but we map it to "카페/간식" in DB
        db_conn.execute(
            "INSERT INTO category_merchant_mappings (category_id, merchant_pattern, match_type, confidence, source) "
            "VALUES (1, '음식테스트', 'exact', 100, 'test')"
        )
        db_conn.commit()

        # Database should win
        assert matcher.get_category('음식테스트') == '카페/간식'


class TestCategoryMatcherEdgeCases:
    """Test edge cases and error handling."""

    @pytest.fixture
    def db_conn_with_missing_category(self):
        """Create database with mapping pointing to non-existent category."""
        conn = sqlite3.connect(':memory:')
        conn.row_factory = sqlite3.Row

        conn.execute('''
            CREATE TABLE categories (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL UNIQUE,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')

        conn.execute('''
            CREATE TABLE category_merchant_mappings (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                category_id INTEGER NOT NULL,
                merchant_pattern TEXT NOT NULL,
                match_type TEXT NOT NULL CHECK(match_type IN ('exact', 'partial')),
                confidence INTEGER NOT NULL DEFAULT 100 CHECK(confidence >= 0 AND confidence <= 100),
                source TEXT NOT NULL DEFAULT 'manual',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE(category_id, merchant_pattern, match_type)
            )
        ''')

        # Insert mapping pointing to non-existent category (data inconsistency)
        conn.execute(
            "INSERT INTO category_merchant_mappings (category_id, merchant_pattern, match_type, confidence, source) "
            "VALUES (999, '잘못된가게', 'exact', 100, 'test')"
        )
        conn.commit()

        yield conn
        conn.close()

    def test_missing_category_fallback(self, db_conn_with_missing_category):
        """Test fallback when category_id exists but category doesn't."""
        category_repo = CategoryRepository(db_conn_with_missing_category)
        mapping_repo = CategoryMerchantMappingRepository(db_conn_with_missing_category)
        matcher = CategoryMatcher(mapping_repo=mapping_repo, category_repo=category_repo)

        # Should fall back to keyword rules (which have no match), then default
        # Since "잘못된가게" doesn't match any keyword, should return '기타'
        assert matcher.get_category('잘못된가게') == '기타'


if __name__ == '__main__':
    pytest.main([__file__, '-v'])
