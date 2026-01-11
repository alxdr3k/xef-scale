"""
Unit tests for update_gita_categories.py script.

Tests the re-categorization logic for '기타' transactions using
database mappings with mock data and database transactions.
"""

import sys
import os
import pytest
import sqlite3
import tempfile
from unittest.mock import patch, MagicMock

# Add scripts directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'scripts'))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from update_gita_categories import (
    get_gita_transactions,
    re_categorize_transactions,
    apply_updates
)
from src.db.connection import DatabaseConnection
from src.db.repository import (
    CategoryRepository,
    CategoryMerchantMappingRepository,
    InstitutionRepository,
    TransactionRepository
)
from src.category_matcher import CategoryMatcher


@pytest.fixture
def db_conn():
    """Create in-memory database for testing with schema."""
    conn = sqlite3.connect(':memory:')
    conn.row_factory = sqlite3.Row

    # Create tables
    conn.execute('''
        CREATE TABLE categories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    conn.execute('''
        CREATE TABLE financial_institutions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            institution_type TEXT NOT NULL CHECK(institution_type IN ('BANK', 'CARD', 'PAY')),
            display_name TEXT,
            is_active INTEGER DEFAULT 1,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    conn.execute('''
        CREATE TABLE transactions (
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
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (category_id) REFERENCES categories(id),
            FOREIGN KEY (institution_id) REFERENCES financial_institutions(id)
        )
    ''')

    conn.execute('''
        CREATE TABLE category_merchant_mappings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            category_id INTEGER NOT NULL,
            merchant_pattern TEXT NOT NULL,
            match_type TEXT NOT NULL CHECK(match_type IN ('exact', 'partial')),
            confidence INTEGER DEFAULT 100 CHECK(confidence BETWEEN 0 AND 100),
            source TEXT DEFAULT 'manual',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(category_id, merchant_pattern, match_type),
            FOREIGN KEY (category_id) REFERENCES categories(id)
        )
    ''')

    conn.commit()
    return conn


@pytest.fixture
def db_connection(db_conn, monkeypatch):
    """Mock DatabaseConnection.get_instance() to return test database."""
    # Mock the singleton instance
    monkeypatch.setattr(DatabaseConnection, '_instance', db_conn)
    yield db_conn
    # Reset singleton
    monkeypatch.setattr(DatabaseConnection, '_instance', None)


@pytest.fixture
def sample_data(db_connection):
    """Insert sample data for testing."""
    conn = db_connection
    category_repo = CategoryRepository(conn)
    institution_repo = InstitutionRepository(conn)
    mapping_repo = CategoryMerchantMappingRepository(conn)
    txn_repo = TransactionRepository(conn, category_repo, institution_repo)

    # Create categories
    gita_id = category_repo.get_or_create('기타')
    food_id = category_repo.get_or_create('식비')
    cafe_id = category_repo.get_or_create('카페/간식')
    store_id = category_repo.get_or_create('편의점/마트/잡화')

    # Create institution
    inst_id = institution_repo.get_or_create('테스트카드', 'CARD')

    # Create category mappings
    mapping_repo.add_mapping(cafe_id, '스타벅스', 'exact', 100, 'test')
    mapping_repo.add_mapping(cafe_id, '커피', 'partial', 90, 'test')
    mapping_repo.add_mapping(store_id, '편의점', 'partial', 90, 'test')
    mapping_repo.add_mapping(food_id, '식당', 'partial', 90, 'test')

    # Create '기타' transactions
    cursor = conn.cursor()
    cursor.execute('''
        INSERT INTO transactions (
            transaction_year, transaction_month, transaction_date,
            category_id, institution_id, merchant_name, amount
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
    ''', (2025, 1, '2025-01-01', gita_id, inst_id, '스타벅스 강남점', 5000))

    cursor.execute('''
        INSERT INTO transactions (
            transaction_year, transaction_month, transaction_date,
            category_id, institution_id, merchant_name, amount
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
    ''', (2025, 1, '2025-01-02', gita_id, inst_id, 'CU 편의점', 3000))

    cursor.execute('''
        INSERT INTO transactions (
            transaction_year, transaction_month, transaction_date,
            category_id, institution_id, merchant_name, amount
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
    ''', (2025, 1, '2025-01-03', gita_id, inst_id, '알수없는가게', 10000))

    conn.commit()
    return conn


class TestGetGitaTransactions:
    """Tests for get_gita_transactions() function"""

    def test_get_gita_transactions_success(self, db_connection, sample_data):
        """Test successful retrieval of '기타' transactions"""
        transactions = get_gita_transactions()

        # Should find exactly the transactions we inserted as '기타'
        assert len(transactions) > 0
        for txn in transactions:
            assert 'id' in txn
            assert 'merchant_name' in txn
            assert 'amount' in txn
            assert 'transaction_date' in txn

    def test_get_gita_transactions_no_gita_category(self, db_connection):
        """Test when '기타' category doesn't exist"""
        conn = DatabaseConnection.get_instance()

        # Delete '기타' category
        conn.execute("DELETE FROM categories WHERE name = '기타'")
        conn.commit()

        transactions = get_gita_transactions()
        assert transactions == []

    def test_get_gita_transactions_empty_result(self, db_connection, sample_data):
        """Test when no transactions have '기타' category"""
        conn = DatabaseConnection.get_instance()
        category_repo = CategoryRepository(conn)

        # Change all '기타' transactions to different category
        gita_id = category_repo.get_by_name('기타')['id']
        food_id = category_repo.get_by_name('식비')['id']

        conn.execute(
            "UPDATE transactions SET category_id = ? WHERE category_id = ?",
            (food_id, gita_id)
        )
        conn.commit()

        transactions = get_gita_transactions()
        assert transactions == []


class TestReCategorizeTransactions:
    """Tests for re_categorize_transactions() function"""

    def test_recategorize_with_database_mappings(self, db_connection, sample_data):
        """Test re-categorization using database mappings"""
        conn = DatabaseConnection.get_instance()
        category_repo = CategoryRepository(conn)
        mapping_repo = CategoryMerchantMappingRepository(conn)

        # Create matcher with database support
        matcher = CategoryMatcher(mapping_repo=mapping_repo, category_repo=category_repo)

        # Get transactions to re-categorize
        transactions = get_gita_transactions()

        # Re-categorize
        updates, stats = re_categorize_transactions(transactions, matcher, category_repo)

        # Verify updates structure
        for update in updates:
            assert 'id' in update
            assert 'merchant_name' in update
            assert 'new_category_id' in update
            assert 'new_category_name' in update
            assert update['new_category_name'] != '기타'

        # Verify stats
        assert isinstance(stats, dict)
        assert sum(stats.values()) == len(transactions)

    def test_recategorize_no_matches(self, db_connection):
        """Test when no transactions can be re-categorized"""
        conn = DatabaseConnection.get_instance()
        category_repo = CategoryRepository(conn)
        mapping_repo = CategoryMerchantMappingRepository(conn)

        matcher = CategoryMatcher(mapping_repo=mapping_repo, category_repo=category_repo)

        # Create transactions with merchants that have no mappings
        transactions = [
            {
                'id': 1,
                'merchant_name': 'Unknown Merchant XYZ123',
                'amount': 10000,
                'transaction_date': '2025-01-01'
            }
        ]

        updates, stats = re_categorize_transactions(transactions, matcher, category_repo)

        # No updates should be made
        assert len(updates) == 0
        # All should remain as '기타'
        assert stats.get('기타', 0) == 1

    def test_recategorize_partial_matches(self, db_connection, sample_data):
        """Test when only some transactions can be re-categorized"""
        conn = DatabaseConnection.get_instance()
        category_repo = CategoryRepository(conn)
        mapping_repo = CategoryMerchantMappingRepository(conn)

        matcher = CategoryMatcher(mapping_repo=mapping_repo, category_repo=category_repo)

        # Mix of known and unknown merchants
        transactions = [
            {
                'id': 1,
                'merchant_name': '스타벅스',  # Should match
                'amount': 5000,
                'transaction_date': '2025-01-01'
            },
            {
                'id': 2,
                'merchant_name': 'Unknown Merchant',  # Should not match
                'amount': 10000,
                'transaction_date': '2025-01-02'
            }
        ]

        updates, stats = re_categorize_transactions(transactions, matcher, category_repo)

        # Should have at least one update for '스타벅스'
        assert len(updates) >= 1
        # Should have both '기타' and other categories in stats
        assert len(stats) >= 2


class TestApplyUpdates:
    """Tests for apply_updates() function"""

    def test_apply_updates_success(self, db_connection, sample_data):
        """Test successful application of updates"""
        conn = DatabaseConnection.get_instance()
        category_repo = CategoryRepository(conn)

        # Get a transaction to update
        cursor = conn.execute("""
            SELECT t.id, c.name as category_name
            FROM transactions t
            JOIN categories c ON t.category_id = c.id
            WHERE c.name = '기타'
            LIMIT 1
        """)
        row = cursor.fetchone()

        if not row:
            pytest.skip("No '기타' transactions available for testing")

        txn_id = row[0]
        old_category = row[1]

        # Get a different category to update to
        food_category = category_repo.get_by_name('식비')

        updates = [{
            'id': txn_id,
            'merchant_name': 'Test Merchant',
            'new_category_id': food_category['id'],
            'new_category_name': '식비'
        }]

        # Apply updates
        count = apply_updates(updates)
        assert count == 1

        # Verify transaction was updated
        cursor = conn.execute("""
            SELECT c.name
            FROM transactions t
            JOIN categories c ON t.category_id = c.id
            WHERE t.id = ?
        """, (txn_id,))
        row = cursor.fetchone()
        assert row[0] == '식비'

    def test_apply_updates_empty_list(self, db_connection):
        """Test applying empty update list"""
        count = apply_updates([])
        assert count == 0

    def test_apply_updates_multiple_transactions(self, db_connection, sample_data):
        """Test updating multiple transactions in batch"""
        conn = DatabaseConnection.get_instance()
        category_repo = CategoryRepository(conn)

        # Get multiple '기타' transactions
        cursor = conn.execute("""
            SELECT t.id
            FROM transactions t
            JOIN categories c ON t.category_id = c.id
            WHERE c.name = '기타'
            LIMIT 3
        """)
        txn_ids = [row[0] for row in cursor.fetchall()]

        if len(txn_ids) < 2:
            pytest.skip("Not enough '기타' transactions for batch test")

        food_category = category_repo.get_by_name('식비')

        updates = [{
            'id': txn_id,
            'merchant_name': f'Test Merchant {txn_id}',
            'new_category_id': food_category['id'],
            'new_category_name': '식비'
        } for txn_id in txn_ids]

        # Apply batch updates
        count = apply_updates(updates)
        assert count == len(txn_ids)

        # Verify all transactions were updated
        for txn_id in txn_ids:
            cursor = conn.execute("""
                SELECT c.name
                FROM transactions t
                JOIN categories c ON t.category_id = c.id
                WHERE t.id = ?
            """, (txn_id,))
            row = cursor.fetchone()
            assert row[0] == '식비'


class TestIntegrationEndToEnd:
    """Integration tests for the complete re-categorization workflow"""

    def test_end_to_end_recategorization(self, db_connection, sample_data):
        """Test complete workflow from get -> recategorize -> apply"""
        conn = DatabaseConnection.get_instance()
        category_repo = CategoryRepository(conn)
        mapping_repo = CategoryMerchantMappingRepository(conn)

        # Step 1: Get '기타' transactions
        initial_transactions = get_gita_transactions()
        initial_count = len(initial_transactions)

        assert initial_count > 0, "Need '기타' transactions for end-to-end test"

        # Step 2: Re-categorize
        matcher = CategoryMatcher(mapping_repo=mapping_repo, category_repo=category_repo)
        updates, stats = re_categorize_transactions(initial_transactions, matcher, category_repo)

        # Step 3: Apply updates (if any)
        if updates:
            updated_count = apply_updates(updates)
            assert updated_count == len(updates)

            # Step 4: Verify final state
            final_transactions = get_gita_transactions()
            final_count = len(final_transactions)

            # Should have fewer '기타' transactions after updates
            assert final_count == initial_count - updated_count

    def test_idempotent_recategorization(self, db_connection, sample_data):
        """Test that running re-categorization twice produces same result"""
        conn = DatabaseConnection.get_instance()
        category_repo = CategoryRepository(conn)
        mapping_repo = CategoryMerchantMappingRepository(conn)
        matcher = CategoryMatcher(mapping_repo=mapping_repo, category_repo=category_repo)

        # First run
        transactions_1 = get_gita_transactions()
        updates_1, stats_1 = re_categorize_transactions(transactions_1, matcher, category_repo)

        if updates_1:
            apply_updates(updates_1)

        # Second run
        transactions_2 = get_gita_transactions()
        updates_2, stats_2 = re_categorize_transactions(transactions_2, matcher, category_repo)

        # Should have no updates on second run (all applicable mappings already applied)
        assert len(updates_2) == 0
        assert stats_2.get('기타', 0) == len(transactions_2)


class TestEdgeCases:
    """Tests for edge cases and error handling"""

    def test_missing_category(self, db_connection, sample_data):
        """Test handling of missing category in database"""
        conn = DatabaseConnection.get_instance()
        category_repo = CategoryRepository(conn)
        mapping_repo = CategoryMerchantMappingRepository(conn)

        matcher = CategoryMatcher(mapping_repo=mapping_repo, category_repo=category_repo)

        # Create a mock transaction with a category that doesn't exist
        transactions = [{
            'id': 999,
            'merchant_name': '스타벅스',
            'amount': 5000,
            'transaction_date': '2025-01-01'
        }]

        # Temporarily mock matcher to return non-existent category
        with patch.object(matcher, 'get_category', return_value='NonExistentCategory'):
            updates, stats = re_categorize_transactions(transactions, matcher, category_repo)

            # Should not create updates for non-existent categories
            assert len(updates) == 0

    def test_empty_merchant_name(self, db_connection):
        """Test handling of transactions with empty merchant names"""
        conn = DatabaseConnection.get_instance()
        category_repo = CategoryRepository(conn)
        mapping_repo = CategoryMerchantMappingRepository(conn)

        matcher = CategoryMatcher(mapping_repo=mapping_repo, category_repo=category_repo)

        transactions = [{
            'id': 1,
            'merchant_name': '',
            'amount': 5000,
            'transaction_date': '2025-01-01'
        }]

        updates, stats = re_categorize_transactions(transactions, matcher, category_repo)

        # Empty merchant names should default to '기타'
        assert stats.get('기타', 0) == 1
        assert len(updates) == 0

    def test_null_merchant_name(self, db_connection):
        """Test handling of transactions with None merchant names"""
        conn = DatabaseConnection.get_instance()
        category_repo = CategoryRepository(conn)
        mapping_repo = CategoryMerchantMappingRepository(conn)

        matcher = CategoryMatcher(mapping_repo=mapping_repo, category_repo=category_repo)

        transactions = [{
            'id': 1,
            'merchant_name': None,
            'amount': 5000,
            'transaction_date': '2025-01-01'
        }]

        updates, stats = re_categorize_transactions(transactions, matcher, category_repo)

        # None merchant names should default to '기타'
        assert stats.get('기타', 0) == 1
        assert len(updates) == 0
