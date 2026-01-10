"""
Integration tests for database layer.
Tests full workflow from connection to repository operations.
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


class TestDatabaseIntegration(unittest.TestCase):
    """
    Integration tests for database operations.

    Creates temporary database for each test to avoid polluting
    production data. Tests full workflow including migrations,
    inserts, queries, and duplicate handling.
    """

    @classmethod
    def setUpClass(cls):
        """Set up test environment once for all tests."""
        # Create temp directory for test database
        cls.temp_dir = tempfile.mkdtemp()
        cls.original_data_dir = DIRECTORIES['data']

        # Override data directory to use temp directory
        DIRECTORIES['data'] = cls.temp_dir

    @classmethod
    def tearDownClass(cls):
        """Clean up test environment after all tests."""
        # Restore original data directory
        DIRECTORIES['data'] = cls.original_data_dir

        # Close connection and cleanup
        DatabaseConnection.close()

        # Remove temp directory
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
            conn,
            self.category_repo,
            self.institution_repo
        )

    def tearDown(self):
        """Clean up after each test."""
        # Close connection
        DatabaseConnection.close()

    def test_import_from_module(self):
        """Test that module exports work correctly."""
        from src.db import DatabaseConnection as DBConn
        from src.db import CategoryRepository as CatRepo
        from src.db import InstitutionRepository as InstRepo
        from src.db import TransactionRepository as TxnRepo

        self.assertIsNotNone(DBConn)
        self.assertIsNotNone(CatRepo)
        self.assertIsNotNone(InstRepo)
        self.assertIsNotNone(TxnRepo)

    def test_insert_and_query(self):
        """Test inserting transaction and querying it back."""
        # Create sample transaction
        txn = Transaction(
            month='09',
            date='2025.09.13',
            category='식비',
            item='스타벅스',
            amount=5000,
            source='하나카드'
        )

        # Insert via repository
        txn_id = self.transaction_repo.insert(txn)
        self.assertGreater(txn_id, 0, 'Insert should return positive ID')

        # Query back by year
        results = self.transaction_repo.get_by_year(2025)
        self.assertEqual(len(results), 1, 'Should have exactly 1 transaction')
        self.assertEqual(results[0]['merchant_name'], '스타벅스')
        self.assertEqual(results[0]['amount'], 5000)

        # Verify date format conversion (yyyy.mm.dd -> yyyy-mm-dd)
        self.assertEqual(results[0]['transaction_date'], '2025-09-13')

    def test_date_format_conversion(self):
        """Test that date format is correctly converted."""
        txn = Transaction(
            month='12',
            date='2025.12.25',
            category='쇼핑',
            item='크리스마스 선물',
            amount=100000,
            source='신한카드'
        )

        self.transaction_repo.insert(txn)

        # Verify date stored in correct format
        conn = DatabaseConnection.get_instance()
        cursor = conn.execute(
            'SELECT transaction_date FROM transactions WHERE merchant_name = ?',
            ('크리스마스 선물',)
        )
        result = cursor.fetchone()

        self.assertIsNotNone(result)
        self.assertEqual(result['transaction_date'], '2025-12-25')

    def test_duplicate_handling(self):
        """
        Test that duplicate transactions are ignored.

        Note: UNIQUE constraint includes installment_current field.
        Transactions with NULL installment_current are treated as distinct by SQL.
        This test uses transactions WITH installment info to properly test deduplication.
        """
        # Create transaction with installment info (so UNIQUE constraint works properly)
        txn = Transaction(
            month='10',
            date='2025.10.15',
            category='교통',
            item='지하철',
            amount=1500,
            source='카카오페이',
            installment_months=3,
            installment_current=1,
            original_amount=4500
        )

        # Insert first time
        id1 = self.transaction_repo.insert(txn)
        self.assertGreater(id1, 0)

        # Insert duplicate (should be ignored by UNIQUE constraint)
        id2 = self.transaction_repo.insert(txn)

        # Query to verify only one row exists
        results = self.transaction_repo.get_by_year(2025)
        self.assertEqual(len(results), 1, 'Duplicate should be ignored when all fields including installment_current match')

    def test_batch_insert(self):
        """Test batch insert with multiple transactions."""
        transactions = [
            Transaction(
                month='11',
                date='2025.11.01',
                category='식비',
                item='점심',
                amount=10000,
                source='하나카드'
            ),
            Transaction(
                month='11',
                date='2025.11.02',
                category='교통',
                item='택시',
                amount=8000,
                source='토스페이'
            ),
            Transaction(
                month='11',
                date='2025.11.03',
                category='통신',
                item='인터넷',
                amount=50000,
                source='카카오뱅크'
            )
        ]

        # Batch insert
        count = self.transaction_repo.batch_insert(transactions)
        self.assertEqual(count, 3, 'Should insert all 3 transactions')

        # Verify in database
        results = self.transaction_repo.get_by_year(2025)
        self.assertEqual(len(results), 3)

    def test_monthly_summary(self):
        """Test monthly summary aggregation."""
        # Insert transactions in different categories
        transactions = [
            Transaction(
                month='09',
                date='2025.09.10',
                category='식비',
                item='아침',
                amount=5000,
                source='하나카드'
            ),
            Transaction(
                month='09',
                date='2025.09.11',
                category='식비',
                item='저녁',
                amount=15000,
                source='하나카드'
            ),
            Transaction(
                month='09',
                date='2025.09.12',
                category='교통',
                item='버스',
                amount=3000,
                source='토스페이'
            )
        ]

        self.transaction_repo.batch_insert(transactions)

        # Get monthly summary
        summary = self.transaction_repo.get_monthly_summary(2025, 9)

        # Verify results
        self.assertGreater(len(summary), 0, 'Should have summary data')

        # Find 식비 category
        food_summary = [s for s in summary if s['category'] == '식비']
        self.assertEqual(len(food_summary), 1)
        self.assertEqual(food_summary[0]['total'], 20000)  # 5000 + 15000

        # Find 교통 category
        transport_summary = [s for s in summary if s['category'] == '교통']
        self.assertEqual(len(transport_summary), 1)
        self.assertEqual(transport_summary[0]['total'], 3000)

    def test_category_caching(self):
        """Test that category lookups use cache."""
        # Get category multiple times
        id1 = self.category_repo.get_or_create('식비')
        id2 = self.category_repo.get_or_create('식비')
        id3 = self.category_repo.get_or_create('식비')

        # All should return same ID
        self.assertEqual(id1, id2)
        self.assertEqual(id2, id3)

        # Verify only one row exists
        conn = DatabaseConnection.get_instance()
        cursor = conn.execute("SELECT COUNT(*) FROM categories WHERE name = '식비'")
        count = cursor.fetchone()[0]
        self.assertEqual(count, 1, 'Should have only one row despite multiple calls')

    def test_institution_type_inference(self):
        """Test institution type inference from name."""
        # Test card inference
        card_id = self.institution_repo.get_or_create('테스트카드')
        inst = self.institution_repo.get_by_name('테스트카드')
        self.assertEqual(inst['institution_type'], 'CARD')

        # Test bank inference
        bank_id = self.institution_repo.get_or_create('테스트뱅크')
        inst = self.institution_repo.get_by_name('테스트뱅크')
        self.assertEqual(inst['institution_type'], 'BANK')

        # Test pay inference
        pay_id = self.institution_repo.get_or_create('테스트페이')
        inst = self.institution_repo.get_by_name('테스트페이')
        self.assertEqual(inst['institution_type'], 'PAY')

    def test_installment_transactions(self):
        """Test transactions with installment fields."""
        txn = Transaction(
            month='12',
            date='2025.12.01',
            category='쇼핑',
            item='노트북',
            amount=200000,
            source='신한카드',
            installment_months=12,
            installment_current=1,
            original_amount=2400000
        )

        txn_id = self.transaction_repo.insert(txn)
        self.assertGreater(txn_id, 0)

        # Verify installment fields stored correctly
        conn = DatabaseConnection.get_instance()
        cursor = conn.execute(
            'SELECT installment_months, installment_current, original_amount FROM transactions WHERE id = ?',
            (txn_id,)
        )
        result = cursor.fetchone()

        self.assertEqual(result['installment_months'], 12)
        self.assertEqual(result['installment_current'], 1)
        self.assertEqual(result['original_amount'], 2400000)


if __name__ == '__main__':
    unittest.main(verbosity=2)
