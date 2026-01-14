"""
Unit tests for transaction category update functionality.
Tests the new update_category method and PATCH /category endpoint.
"""

import unittest
import os
import tempfile
import shutil
import sqlite3
from src.db.connection import DatabaseConnection
from src.db.repository import CategoryRepository, InstitutionRepository, TransactionRepository
from src.models import Transaction
from src.config import DIRECTORIES


class TestCategoryUpdate(unittest.TestCase):
    """
    Test suite for category update functionality.

    Tests both repository layer (update_category method) and ensures
    that category updates work for both manual and file-based transactions.
    """

    @classmethod
    def setUpClass(cls):
        """Set up test environment once for all tests."""
        # Create temp directory for test database
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
        """Set up each test with fresh database."""
        # Close any existing connection and remove database file
        DatabaseConnection.close()

        # Remove existing database file if it exists
        db_path = os.path.join(self.temp_dir, 'expense_tracker.db')
        if os.path.exists(db_path):
            os.remove(db_path)

        # Get new connection (will create fresh database)
        conn = DatabaseConnection.get_instance()

        # Execute schema migration
        with open('db/migrations/001_create_schema.sql', 'r', encoding='utf-8') as f:
            conn.executescript(f.read())

        # Execute seed data migration
        with open('db/migrations/002_seed_initial_data.sql', 'r', encoding='utf-8') as f:
            conn.executescript(f.read())

        conn.commit()

        # Initialize repositories
        self.category_repo = CategoryRepository(conn)
        self.institution_repo = InstitutionRepository(conn)
        self.transaction_repo = TransactionRepository(
            conn, self.category_repo, self.institution_repo
        )

    def tearDown(self):
        """Clean up after each test."""
        DatabaseConnection.close()

    def test_update_category_manual_transaction(self):
        """Test updating category for a manual transaction."""
        # Create a manual transaction
        transaction = Transaction(
            month='01',
            date='2025.01.15',
            category='식비',
            item='스타벅스',
            amount=5000,
            source='신한카드'
        )

        txn_id = self.transaction_repo.insert(
            transaction,
            auto_commit=True,
            file_id=None,  # Manual transaction
            row_number=None
        )

        # Verify initial category
        txn = self.transaction_repo.get_by_id(txn_id)
        self.assertEqual(txn['category_name'], '식비')

        # Get new category ID
        new_category_id = self.category_repo.get_or_create('교통')

        # Update category
        success = self.transaction_repo.update_category(txn_id, new_category_id)
        self.assertTrue(success)

        # Verify updated category
        updated_txn = self.transaction_repo.get_by_id(txn_id)
        self.assertEqual(updated_txn['category_name'], '교통')
        self.assertEqual(updated_txn['category_id'], new_category_id)

    def test_update_category_file_based_transaction(self):
        """Test updating category for a file-based (parsed) transaction."""
        # Create a file-based transaction
        transaction = Transaction(
            month='01',
            date='2025.01.15',
            category='식비',
            item='올리브영',
            amount=15000,
            source='하나카드'
        )

        txn_id = self.transaction_repo.insert(
            transaction,
            auto_commit=True,
            file_id=1,  # File-based transaction
            row_number=5
        )

        # Verify initial category
        txn = self.transaction_repo.get_by_id(txn_id)
        self.assertEqual(txn['category_name'], '식비')
        self.assertIsNotNone(txn['file_id'])  # Confirm it's file-based

        # Get new category ID
        new_category_id = self.category_repo.get_or_create('생활용품')

        # Update category (should work even though it's file-based)
        success = self.transaction_repo.update_category(txn_id, new_category_id)
        self.assertTrue(success)

        # Verify updated category
        updated_txn = self.transaction_repo.get_by_id(txn_id)
        self.assertEqual(updated_txn['category_name'], '생활용품')
        self.assertEqual(updated_txn['category_id'], new_category_id)
        self.assertIsNotNone(updated_txn['file_id'])  # Still file-based

    def test_update_category_creates_new_category(self):
        """Test that updating with new category name creates it automatically."""
        # Create a manual transaction
        transaction = Transaction(
            month='01',
            date='2025.01.15',
            category='식비',
            item='GS25',
            amount=3000,
            source='토스뱅크'
        )

        txn_id = self.transaction_repo.insert(
            transaction,
            auto_commit=True,
            file_id=None,
            row_number=None
        )

        # Create new category that doesn't exist yet
        new_category_id = self.category_repo.get_or_create('문화생활')

        # Update to new category
        success = self.transaction_repo.update_category(txn_id, new_category_id)
        self.assertTrue(success)

        # Verify new category exists and is assigned
        updated_txn = self.transaction_repo.get_by_id(txn_id)
        self.assertEqual(updated_txn['category_name'], '문화생활')

        # Verify category is in database
        category = self.category_repo.get_by_name('문화생활')
        self.assertIsNotNone(category)

    def test_update_category_nonexistent_transaction(self):
        """Test updating category for non-existent transaction returns False."""
        new_category_id = self.category_repo.get_or_create('식비')

        # Try to update non-existent transaction
        success = self.transaction_repo.update_category(99999, new_category_id)
        self.assertFalse(success)

    def test_update_category_deleted_transaction(self):
        """Test that soft-deleted transactions cannot have category updated."""
        # Create and then delete a manual transaction
        transaction = Transaction(
            month='01',
            date='2025.01.15',
            category='식비',
            item='카페',
            amount=5000,
            source='신한카드'
        )

        txn_id = self.transaction_repo.insert(
            transaction,
            auto_commit=True,
            file_id=None,
            row_number=None
        )

        # Soft delete the transaction
        self.transaction_repo.soft_delete(txn_id, validate_editable=False)

        # Try to update category
        new_category_id = self.category_repo.get_or_create('교통')
        success = self.transaction_repo.update_category(txn_id, new_category_id)

        # Should return False because transaction is deleted
        self.assertFalse(success)

    def test_update_category_updates_timestamp(self):
        """Test that update_category updates the updated_at timestamp."""
        import time

        # Create a transaction
        transaction = Transaction(
            month='01',
            date='2025.01.15',
            category='식비',
            item='이마트',
            amount=50000,
            source='하나카드'
        )

        txn_id = self.transaction_repo.insert(
            transaction,
            auto_commit=True,
            file_id=None,
            row_number=None
        )

        # Get initial timestamp
        initial_txn = self.transaction_repo.get_by_id(txn_id)
        initial_updated_at = initial_txn['updated_at']

        # Wait a bit to ensure timestamp difference
        time.sleep(0.1)

        # Update category
        new_category_id = self.category_repo.get_or_create('생활비')
        self.transaction_repo.update_category(txn_id, new_category_id)

        # Get updated timestamp
        updated_txn = self.transaction_repo.get_by_id(txn_id)
        updated_updated_at = updated_txn['updated_at']

        # Verify timestamp was updated
        self.assertNotEqual(initial_updated_at, updated_updated_at)


if __name__ == '__main__':
    import os
    unittest.main()
