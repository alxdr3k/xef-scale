"""
Unit tests for automatic category-merchant mapping on transaction category updates.

Tests the feature where changing a transaction's category automatically creates
or updates a merchant mapping for future auto-categorization.
"""

import unittest
import sqlite3
import tempfile
import shutil
import os
from unittest.mock import patch, MagicMock
from fastapi.testclient import TestClient

from backend.main import app
from backend.api.schemas import UserInfo
from src.db.connection import DatabaseConnection
from src.db.repository import (
    CategoryRepository,
    InstitutionRepository,
    TransactionRepository,
    CategoryMerchantMappingRepository
)
from src.models import Transaction
from src.config import DIRECTORIES


class TestCategoryAutoMapping(unittest.TestCase):
    """
    Unit tests for automatic merchant mapping when users update transaction categories.

    Tests the integration between transaction category updates and the merchant
    mapping system to ensure user corrections are automatically learned.
    """

    @classmethod
    def setUpClass(cls):
        """Set up test environment once for all tests."""
        cls.temp_dir = tempfile.mkdtemp()
        cls.original_data_dir = DIRECTORIES['data']
        DIRECTORIES['data'] = cls.temp_dir

    @classmethod
    def tearDownClass(cls):
        """Clean up test environment after all tests."""
        DIRECTORIES['data'] = cls.original_data_dir
        DatabaseConnection.close()
        shutil.rmtree(cls.temp_dir)

    def setUp(self):
        """Set up each test with fresh database and test data."""
        DatabaseConnection.close()

        db_path = os.path.join(self.temp_dir, 'expense_tracker.db')
        if os.path.exists(db_path):
            os.remove(db_path)

        self.conn = DatabaseConnection.get_instance()

        # Create schema from migrations
        migrations = [
            'db/migrations/001_create_schema.sql',
            'db/migrations/002_seed_initial_data.sql',
            'db/migrations/004_add_file_tracking.sql',
            'db/migrations/009_add_soft_delete.sql',
            'db/migrations/010_fix_duplicate_detection.sql'
        ]

        for migration_path in migrations:
            with open(migration_path, 'r', encoding='utf-8') as f:
                self.conn.executescript(f.read())

        # Manually create category_merchant_mappings table (skip full migration 007 due to _migrations table dependency)
        self.conn.executescript('''
            CREATE TABLE IF NOT EXISTS category_merchant_mappings (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                category_id INTEGER NOT NULL,
                merchant_pattern TEXT NOT NULL,
                match_type TEXT NOT NULL CHECK(match_type IN ('exact', 'partial')),
                confidence INTEGER DEFAULT 100 CHECK(confidence >= 0 AND confidence <= 100),
                source TEXT DEFAULT 'imported',
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE CASCADE,
                UNIQUE(category_id, merchant_pattern, match_type)
            );

            CREATE INDEX idx_merchant_pattern ON category_merchant_mappings(merchant_pattern);
            CREATE INDEX idx_category_mappings ON category_merchant_mappings(category_id);
            CREATE INDEX idx_match_type ON category_merchant_mappings(match_type);
            CREATE INDEX idx_merchant_lookup ON category_merchant_mappings(merchant_pattern, match_type);

            CREATE TRIGGER update_category_merchant_mappings_timestamp
            AFTER UPDATE ON category_merchant_mappings
            BEGIN
                UPDATE category_merchant_mappings SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
            END;
        ''')

        self.conn.commit()

        # Initialize repositories
        self.category_repo = CategoryRepository(self.conn)
        self.institution_repo = InstitutionRepository(self.conn)
        self.transaction_repo = TransactionRepository(
            self.conn, self.category_repo, self.institution_repo
        )
        self.mapping_repo = CategoryMerchantMappingRepository(self.conn)

        # Create test data
        self._create_test_data()

        # Mock authentication
        self.mock_user = UserInfo(
            id="test-user-123",
            email="test@example.com",
            name="Test User",
            picture=None,
            username="testuser"
        )

        app.dependency_overrides = {}

        from backend.api.dependencies import get_current_user, get_db

        def override_get_current_user():
            return self.mock_user

        def override_get_db():
            return self.conn

        app.dependency_overrides[get_current_user] = override_get_current_user
        app.dependency_overrides[get_db] = override_get_db

        self.client = TestClient(app)

    def tearDown(self):
        """Clean up after each test."""
        app.dependency_overrides = {}
        DatabaseConnection.close()

    def _create_test_data(self):
        """Create test categories, institutions, and transactions."""
        # Categories are seeded by migration, get IDs
        self.food_category_id = self.category_repo.get_or_create('식비')
        self.transport_category_id = self.category_repo.get_or_create('교통')
        self.shopping_category_id = self.category_repo.get_or_create('편의점/마트/잡화')

        # Institutions are seeded by migration (table is named financial_institutions)
        cursor = self.conn.execute("SELECT id FROM financial_institutions WHERE name = '신한카드'")
        row = cursor.fetchone()
        self.shinhan_id = row['id']

        # Create test transactions using Transaction model
        txn1 = Transaction(
            month='01',
            date='2025.01.15',
            category='기타',
            item='스타벅스 강남점',
            amount=5500,
            source='신한카드'
        )
        self.transaction_id_1 = self.transaction_repo.insert(txn1, auto_commit=True)

        txn2 = Transaction(
            month='01',
            date='2025.01.16',
            category='기타',
            item='지하철 교통비',
            amount=1250,
            source='신한카드'
        )
        self.transaction_id_2 = self.transaction_repo.insert(txn2, auto_commit=True)

        txn3 = Transaction(
            month='01',
            date='2025.01.17',
            category='기타',
            item='스타벅스 강남점',
            amount=6000,
            source='신한카드'
        )
        self.transaction_id_3 = self.transaction_repo.insert(txn3, auto_commit=True)

    def test_category_change_creates_new_mapping(self):
        """
        Test that changing a transaction's category creates a new merchant mapping.

        Scenario: User changes transaction from '기타' to '식비'
        Expected: New mapping created with merchant='스타벅스 강남점', category='식비'
        """
        # Change category from '기타' to '식비'
        response = self.client.patch(
            f"/api/transactions/{self.transaction_id_1}/category",
            json={"category": "식비"}
        )

        self.assertEqual(response.status_code, 200)

        # Verify mapping was created
        category_id = self.mapping_repo.get_category_by_merchant('스타벅스 강남점')
        self.assertIsNotNone(category_id, "Mapping should be created")
        self.assertEqual(category_id, self.food_category_id, "Mapping should point to 식비 category")

        # Verify mapping details in database
        cursor = self.conn.execute('''
            SELECT category_id, merchant_pattern, match_type, confidence, source
            FROM category_merchant_mappings
            WHERE merchant_pattern = '스타벅스 강남점'
        ''')
        row = cursor.fetchone()

        self.assertIsNotNone(row, "Mapping record should exist")
        self.assertEqual(row['category_id'], self.food_category_id)
        self.assertEqual(row['match_type'], 'exact')
        self.assertEqual(row['confidence'], 100)
        self.assertEqual(row['source'], 'user_manual')

    def test_category_change_updates_existing_mapping(self):
        """
        Test that changing category again updates existing mapping instead of creating duplicate.

        Scenario:
        1. User changes transaction to '식비' (creates mapping)
        2. User changes same merchant transaction to '편의점/마트/잡화' (updates mapping)
        Expected: Only one mapping exists with updated category
        """
        # First change: 기타 -> 식비
        response1 = self.client.patch(
            f"/api/transactions/{self.transaction_id_1}/category",
            json={"category": "식비"}
        )
        self.assertEqual(response1.status_code, 200)

        # Verify first mapping
        category_id = self.mapping_repo.get_category_by_merchant('스타벅스 강남점')
        self.assertEqual(category_id, self.food_category_id)

        # Second change: 식비 -> 편의점/마트/잡화 (different transaction, same merchant)
        response2 = self.client.patch(
            f"/api/transactions/{self.transaction_id_3}/category",
            json={"category": "편의점/마트/잡화"}
        )
        self.assertEqual(response2.status_code, 200)

        # Verify mapping was updated, not duplicated
        category_id = self.mapping_repo.get_category_by_merchant('스타벅스 강남점')
        self.assertEqual(category_id, self.shopping_category_id, "Mapping should be updated")

        # Verify only one mapping exists
        cursor = self.conn.execute('''
            SELECT COUNT(*) as count
            FROM category_merchant_mappings
            WHERE merchant_pattern = '스타벅스 강남점' AND match_type = 'exact'
        ''')
        row = cursor.fetchone()
        self.assertEqual(row['count'], 1, "Should only have one mapping for this merchant")

    def test_mapping_failure_does_not_break_transaction_update(self):
        """
        Test that mapping errors don't prevent transaction category updates.

        Scenario: Force a mapping error (mock add_mapping to raise exception)
        Expected: Transaction update succeeds despite mapping failure
        """
        # Mock add_mapping at the repository level to raise an exception
        with patch.object(CategoryMerchantMappingRepository, 'add_mapping', side_effect=Exception("Database error")):
            # Update category - should succeed despite mapping error
            response = self.client.patch(
                f"/api/transactions/{self.transaction_id_1}/category",
                json={"category": "식비"}
            )

            self.assertEqual(response.status_code, 200, "Transaction update should succeed")

            # Verify transaction category was updated
            updated_transaction = self.transaction_repo.get_by_id(self.transaction_id_1)
            self.assertEqual(updated_transaction['category_name'], '식비')

    def test_correct_mapping_parameters(self):
        """
        Test that mapping is created with correct parameters.

        Expected parameters:
        - match_type: 'exact'
        - confidence: 100
        - source: 'user_manual'
        - merchant_pattern: exact merchant name from transaction
        """
        response = self.client.patch(
            f"/api/transactions/{self.transaction_id_1}/category",
            json={"category": "식비"}
        )

        self.assertEqual(response.status_code, 200)

        # Verify all parameters are correct
        cursor = self.conn.execute('''
            SELECT category_id, merchant_pattern, match_type, confidence, source
            FROM category_merchant_mappings
            WHERE merchant_pattern = '스타벅스 강남점'
        ''')
        row = cursor.fetchone()

        self.assertEqual(row['category_id'], self.food_category_id, "Should map to correct category")
        self.assertEqual(row['merchant_pattern'], '스타벅스 강남점', "Should use exact merchant name")
        self.assertEqual(row['match_type'], 'exact', "Should use exact match type")
        self.assertEqual(row['confidence'], 100, "Should have 100% confidence")
        self.assertEqual(row['source'], 'user_manual', "Should be marked as user_manual source")

    def test_multiple_different_merchants_create_separate_mappings(self):
        """
        Test that updating different merchants creates separate mappings.

        Scenario: Change categories for two transactions with different merchants
        Expected: Two separate mappings created
        """
        # Update first transaction (스타벅스)
        response1 = self.client.patch(
            f"/api/transactions/{self.transaction_id_1}/category",
            json={"category": "식비"}
        )
        self.assertEqual(response1.status_code, 200)

        # Update second transaction (지하철)
        response2 = self.client.patch(
            f"/api/transactions/{self.transaction_id_2}/category",
            json={"category": "교통"}
        )
        self.assertEqual(response2.status_code, 200)

        # Verify both mappings exist
        starbucks_category = self.mapping_repo.get_category_by_merchant('스타벅스 강남점')
        subway_category = self.mapping_repo.get_category_by_merchant('지하철 교통비')

        self.assertEqual(starbucks_category, self.food_category_id, "Starbucks should map to 식비")
        self.assertEqual(subway_category, self.transport_category_id, "Subway should map to 교통")

        # Verify total count
        cursor = self.conn.execute('''
            SELECT COUNT(*) as count
            FROM category_merchant_mappings
            WHERE match_type = 'exact' AND source = 'user_manual'
        ''')
        row = cursor.fetchone()
        self.assertEqual(row['count'], 2, "Should have two separate mappings")

    def test_transaction_without_merchant_name_skips_mapping(self):
        """
        Test that transactions without merchant_name don't create mappings.

        Scenario: Create transaction with empty merchant_name, update category
        Expected: No mapping created, transaction update succeeds
        """
        # Create transaction with no merchant name
        txn = Transaction(
            month='01',
            date='2025.01.18',
            category='기타',
            item='',  # Empty merchant name
            amount=1000,
            source='신한카드'
        )
        transaction_id = self.transaction_repo.insert(txn, auto_commit=True)

        # Update category
        response = self.client.patch(
            f"/api/transactions/{transaction_id}/category",
            json={"category": "식비"}
        )

        self.assertEqual(response.status_code, 200, "Transaction update should succeed")

        # Verify no mapping was created for empty string
        cursor = self.conn.execute('''
            SELECT COUNT(*) as count
            FROM category_merchant_mappings
            WHERE merchant_pattern = ''
        ''')
        row = cursor.fetchone()
        self.assertEqual(row['count'], 0, "Should not create mapping for empty merchant name")

    def test_category_auto_complete_after_mapping_creation(self):
        """
        Test that future transactions with same merchant can use the mapping.

        Scenario:
        1. User updates transaction category (creates mapping)
        2. Verify mapping can be used for auto-categorization
        Expected: get_category_by_merchant returns correct category
        """
        # Create mapping via transaction update
        response = self.client.patch(
            f"/api/transactions/{self.transaction_id_1}/category",
            json={"category": "식비"}
        )
        self.assertEqual(response.status_code, 200)

        # Simulate new transaction with same merchant - verify mapping works
        category_id = self.mapping_repo.get_category_by_merchant('스타벅스 강남점')

        self.assertIsNotNone(category_id, "Should find mapping")
        self.assertEqual(category_id, self.food_category_id, "Should return correct category")

        # Verify category name
        cursor = self.conn.execute('SELECT name FROM categories WHERE id = ?', (category_id,))
        row = cursor.fetchone()
        self.assertEqual(row['name'], '식비', "Category name should match")


if __name__ == '__main__':
    unittest.main()
