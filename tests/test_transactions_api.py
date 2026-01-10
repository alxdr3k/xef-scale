"""
Unit tests for Transactions API endpoints.

Tests comprehensive filtering, pagination, sorting, and error handling
for all transaction routes.
"""

import unittest
import sqlite3
import tempfile
import shutil
from datetime import datetime
from unittest.mock import Mock, patch
from fastapi import HTTPException
from fastapi.testclient import TestClient

from backend.main import app
from backend.api.schemas import UserInfo
from src.db.connection import DatabaseConnection
from src.db.repository import CategoryRepository, InstitutionRepository, TransactionRepository
from src.models import Transaction
from src.config import DIRECTORIES


class TestTransactionsAPI(unittest.TestCase):
    """
    Unit tests for transaction API endpoints.

    Tests filtering, pagination, sorting, authentication, and error handling
    across all three transaction endpoints.
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
        """Set up each test with fresh database and test data."""
        # Close any existing connection and remove database file
        DatabaseConnection.close()

        import os
        db_path = os.path.join(self.temp_dir, 'expense_tracker.db')
        if os.path.exists(db_path):
            os.remove(db_path)

        # Create fresh database connection
        self.conn = DatabaseConnection.get_instance()

        # Execute all migrations in order
        migrations = [
            'db/migrations/001_create_schema.sql',
            'db/migrations/002_seed_initial_data.sql',
            'db/migrations/004_add_file_tracking.sql',
            'db/migrations/005_add_parsing_sessions.sql',
            'db/migrations/006_add_users_table.sql'
        ]

        for migration_path in migrations:
            with open(migration_path, 'r', encoding='utf-8') as f:
                self.conn.executescript(f.read())

        self.conn.commit()

        # Initialize repositories
        self.category_repo = CategoryRepository(self.conn)
        self.institution_repo = InstitutionRepository(self.conn)
        self.transaction_repo = TransactionRepository(
            self.conn, self.category_repo, self.institution_repo
        )

        # Create test data
        self._create_test_data()

        # Create test client
        self.client = TestClient(app)

        # Mock authentication - all tests use authenticated user
        self.mock_user = UserInfo(
            id="test-user-123",
            email="test@example.com",
            name="Test User",
            picture=None
        )

    def tearDown(self):
        """Clean up after each test."""
        # Close database connection
        if hasattr(self, 'conn'):
            self.conn.close()

    def _create_test_data(self):
        """
        Create comprehensive test data for transaction queries.

        Creates transactions across multiple:
        - Years: 2025, 2026
        - Months: 1, 9
        - Categories: 식비, 교통, 통신
        - Institutions: 하나카드, 신한카드, 토스뱅크
        - Merchants: Various Korean merchant names
        """
        # Test transactions with diverse data
        test_transactions = [
            # 2025-09 transactions
            Transaction('09', '2025.09.01', '식비', '스타벅스 강남점', 5000, '하나카드'),
            Transaction('09', '2025.09.02', '식비', '맥도날드', 8000, '하나카드'),
            Transaction('09', '2025.09.03', '교통', '카카오택시', 12000, '신한카드'),
            Transaction('09', '2025.09.04', '식비', '스타벅스 홍대점', 4500, '토스뱅크'),
            Transaction('09', '2025.09.05', '통신', 'SKT', 55000, '하나카드'),
            Transaction('09', '2025.09.10', '식비', '김밥천국', 6000, '신한카드'),
            Transaction('09', '2025.09.15', '교통', '지하철', 1500, '하나카드'),
            Transaction('09', '2025.09.20', '식비', '이마트', 45000, '토스뱅크'),
            Transaction('09', '2025.09.25', '교통', '버스', 1200, '하나카드'),
            Transaction('09', '2025.09.28', '식비', '올리브영', 23000, '신한카드'),

            # 2026-01 transactions
            Transaction('01', '2026.01.05', '식비', '스타벅스 강남점', 5500, '하나카드'),
            Transaction('01', '2026.01.10', '교통', '카카오택시', 15000, '신한카드'),
            Transaction('01', '2026.01.15', '통신', 'KT', 50000, '하나카드'),
            Transaction('01', '2026.01.20', '식비', '맥도날드', 9000, '토스뱅크'),
            Transaction('01', '2026.01.25', '교통', '지하철', 1500, '신한카드'),

            # Additional 2025-09 for pagination testing (making 50+ total)
            *[Transaction('09', f'2025.09.{i:02d}', '기타', f'상점{i}', 1000 * i, '하나카드')
              for i in range(10, 30)]
        ]

        # Insert all test transactions
        self.transaction_repo.batch_insert(test_transactions)
        self.conn.commit()

    def _mock_auth(self):
        """Helper to mock authentication for test requests."""
        return patch('backend.api.dependencies.get_current_user', return_value=self.mock_user)

    @patch('backend.api.dependencies.get_current_user')
    def test_get_transactions_success(self, mock_get_user):
        """Test GET /api/transactions returns paginated results."""
        mock_get_user.return_value = self.mock_user
        response = self.client.get('/api/transactions')

        self.assertEqual(response.status_code, 200)
        data = response.json()

        # Verify response structure
        self.assertIn('data', data)
        self.assertIn('total', data)
        self.assertIn('page', data)
        self.assertIn('limit', data)
        self.assertIn('total_pages', data)

        # Verify default pagination (page=1, limit=50)
        self.assertEqual(data['page'], 1)
        self.assertEqual(data['limit'], 50)
        self.assertGreater(data['total'], 0)
        self.assertGreater(len(data['data']), 0)

        # Verify transaction structure
        first_txn = data['data'][0]
        self.assertIn('id', first_txn)
        self.assertIn('date', first_txn)
        self.assertIn('category', first_txn)
        self.assertIn('merchant_name', first_txn)
        self.assertIn('amount', first_txn)
        self.assertIn('institution', first_txn)

    def test_get_transactions_pagination(self):
        """Test pagination with different page sizes and page numbers."""
        with self._mock_auth():
            # Get first page with 5 items
            response1 = self.client.get('/api/transactions?page=1&limit=5')
            self.assertEqual(response1.status_code, 200)
            data1 = response1.json()

            self.assertEqual(data1['page'], 1)
            self.assertEqual(data1['limit'], 5)
            self.assertEqual(len(data1['data']), 5)

            # Get second page with 5 items
            response2 = self.client.get('/api/transactions?page=2&limit=5')
            self.assertEqual(response2.status_code, 200)
            data2 = response2.json()

            self.assertEqual(data2['page'], 2)
            self.assertEqual(len(data2['data']), 5)

            # Verify different transactions returned
            ids_page1 = {txn['id'] for txn in data1['data']}
            ids_page2 = {txn['id'] for txn in data2['data']}
            self.assertEqual(len(ids_page1 & ids_page2), 0, "Pages should have no overlapping IDs")

    def test_get_transactions_filter_by_year(self):
        """Test filtering transactions by year."""
        with self._mock_auth():
            # Get 2025 transactions
            response = self.client.get('/api/transactions?year=2025')
            self.assertEqual(response.status_code, 200)
            data = response.json()

            # Verify all transactions are from 2025
            for txn in data['data']:
                self.assertTrue(txn['date'].startswith('2025.'))

            # Get 2026 transactions
            response = self.client.get('/api/transactions?year=2026')
            self.assertEqual(response.status_code, 200)
            data = response.json()

            # Verify all transactions are from 2026
            for txn in data['data']:
                self.assertTrue(txn['date'].startswith('2026.'))

    def test_get_transactions_filter_by_month(self):
        """Test filtering transactions by year and month."""
        with self._mock_auth():
            # Get September 2025 transactions
            response = self.client.get('/api/transactions?year=2025&month=9')
            self.assertEqual(response.status_code, 200)
            data = response.json()

            # Verify all transactions are from 2025-09
            for txn in data['data']:
                self.assertTrue(txn['date'].startswith('2025.09.'))

            # Get January 2026 transactions
            response = self.client.get('/api/transactions?year=2026&month=1')
            self.assertEqual(response.status_code, 200)
            data = response.json()

            # Verify all transactions are from 2026-01
            for txn in data['data']:
                self.assertTrue(txn['date'].startswith('2026.01.'))

    def test_get_transactions_filter_by_category(self):
        """Test filtering transactions by category ID."""
        with self._mock_auth():
            # Get category ID for '식비'
            food_category = self.category_repo.get_by_name('식비')
            self.assertIsNotNone(food_category)

            # Filter by food category
            response = self.client.get(f'/api/transactions?category_id={food_category["id"]}')
            self.assertEqual(response.status_code, 200)
            data = response.json()

            # Verify all transactions are food category
            for txn in data['data']:
                self.assertEqual(txn['category'], '식비')

    def test_get_transactions_filter_by_institution(self):
        """Test filtering transactions by institution ID."""
        with self._mock_auth():
            # Get institution ID for '하나카드'
            hana_institution = self.institution_repo.get_by_name('하나카드')
            self.assertIsNotNone(hana_institution)

            # Filter by Hana Card
            response = self.client.get(f'/api/transactions?institution_id={hana_institution["id"]}')
            self.assertEqual(response.status_code, 200)
            data = response.json()

            # Verify all transactions are from Hana Card
            for txn in data['data']:
                self.assertEqual(txn['institution'], '하나카드')

    def test_get_transactions_search_merchant(self):
        """Test searching transactions by merchant name."""
        with self._mock_auth():
            # Search for Starbucks transactions
            response = self.client.get('/api/transactions?search=스타벅스')
            self.assertEqual(response.status_code, 200)
            data = response.json()

            # Verify all results contain '스타벅스'
            self.assertGreater(len(data['data']), 0)
            for txn in data['data']:
                self.assertIn('스타벅스', txn['merchant_name'])

            # Search for non-existent merchant
            response = self.client.get('/api/transactions?search=존재하지않는상점')
            self.assertEqual(response.status_code, 200)
            data = response.json()
            self.assertEqual(len(data['data']), 0)

    def test_get_transactions_sort_date_desc(self):
        """Test sorting transactions by date descending (most recent first)."""
        with self._mock_auth():
            response = self.client.get('/api/transactions?sort=date_desc&limit=10')
            self.assertEqual(response.status_code, 200)
            data = response.json()

            # Verify descending order
            dates = [txn['date'] for txn in data['data']]
            self.assertEqual(dates, sorted(dates, reverse=True))

    def test_get_transactions_sort_date_asc(self):
        """Test sorting transactions by date ascending (oldest first)."""
        with self._mock_auth():
            response = self.client.get('/api/transactions?sort=date_asc&limit=10')
            self.assertEqual(response.status_code, 200)
            data = response.json()

            # Verify ascending order
            dates = [txn['date'] for txn in data['data']]
            self.assertEqual(dates, sorted(dates))

    def test_get_transactions_sort_amount_desc(self):
        """Test sorting transactions by amount descending (highest first)."""
        with self._mock_auth():
            response = self.client.get('/api/transactions?sort=amount_desc&limit=10')
            self.assertEqual(response.status_code, 200)
            data = response.json()

            # Verify descending order by amount
            amounts = [txn['amount'] for txn in data['data']]
            self.assertEqual(amounts, sorted(amounts, reverse=True))

    def test_get_transactions_sort_amount_asc(self):
        """Test sorting transactions by amount ascending (lowest first)."""
        with self._mock_auth():
            response = self.client.get('/api/transactions?sort=amount_asc&limit=10')
            self.assertEqual(response.status_code, 200)
            data = response.json()

            # Verify ascending order by amount
            amounts = [txn['amount'] for txn in data['data']]
            self.assertEqual(amounts, sorted(amounts))

    def test_get_transactions_invalid_sort(self):
        """Test invalid sort parameter returns 400 error."""
        with self._mock_auth():
            response = self.client.get('/api/transactions?sort=invalid_sort')
            self.assertEqual(response.status_code, 400)

    def test_get_transactions_combined_filters(self):
        """Test combining multiple filters (year, month, category, search)."""
        with self._mock_auth():
            # Get food category
            food_category = self.category_repo.get_by_name('식비')

            # Combine year, month, category filters
            response = self.client.get(
                f'/api/transactions?year=2025&month=9&category_id={food_category["id"]}'
            )
            self.assertEqual(response.status_code, 200)
            data = response.json()

            # Verify all filters applied
            for txn in data['data']:
                self.assertTrue(txn['date'].startswith('2025.09.'))
                self.assertEqual(txn['category'], '식비')

    def test_get_transactions_unauthorized(self):
        """Test GET /api/transactions without authentication returns 401."""
        # No auth mock - should fail
        response = self.client.get('/api/transactions')
        self.assertEqual(response.status_code, 401)

    def test_get_transaction_by_id_success(self):
        """Test GET /api/transactions/{id} returns specific transaction."""
        with self._mock_auth():
            # Get first transaction from list endpoint
            list_response = self.client.get('/api/transactions?limit=1')
            self.assertEqual(list_response.status_code, 200)
            first_txn = list_response.json()['data'][0]

            # Get that transaction by ID
            response = self.client.get(f'/api/transactions/{first_txn["id"]}')
            self.assertEqual(response.status_code, 200)
            data = response.json()

            # Verify same transaction
            self.assertEqual(data['id'], first_txn['id'])
            self.assertEqual(data['merchant_name'], first_txn['merchant_name'])
            self.assertEqual(data['amount'], first_txn['amount'])

    def test_get_transaction_by_id_not_found(self):
        """Test GET /api/transactions/{id} with non-existent ID returns 404."""
        with self._mock_auth():
            # Use ID that doesn't exist (99999)
            response = self.client.get('/api/transactions/99999')
            self.assertEqual(response.status_code, 404)

    def test_get_transaction_by_id_unauthorized(self):
        """Test GET /api/transactions/{id} without authentication returns 401."""
        # No auth mock - should fail
        response = self.client.get('/api/transactions/1')
        self.assertEqual(response.status_code, 401)

    def test_get_monthly_summary_success(self):
        """Test GET /api/transactions/summary/monthly returns category breakdown."""
        with self._mock_auth():
            # Get September 2025 summary
            response = self.client.get('/api/transactions/summary/monthly?year=2025&month=9')
            self.assertEqual(response.status_code, 200)
            data = response.json()

            # Verify response structure
            self.assertEqual(data['year'], 2025)
            self.assertEqual(data['month'], 9)
            self.assertIn('total_amount', data)
            self.assertIn('transaction_count', data)
            self.assertIn('by_category', data)

            # Verify category breakdown exists
            self.assertGreater(len(data['by_category']), 0)

            # Verify category structure
            first_category = data['by_category'][0]
            self.assertIn('category_id', first_category)
            self.assertIn('category_name', first_category)
            self.assertIn('amount', first_category)
            self.assertIn('count', first_category)

            # Verify totals match sum of categories
            total_from_categories = sum(cat['amount'] for cat in data['by_category'])
            self.assertEqual(data['total_amount'], total_from_categories)

            count_from_categories = sum(cat['count'] for cat in data['by_category'])
            self.assertEqual(data['transaction_count'], count_from_categories)

    def test_get_monthly_summary_sorted_by_amount(self):
        """Test monthly summary categories are sorted by amount descending."""
        with self._mock_auth():
            response = self.client.get('/api/transactions/summary/monthly?year=2025&month=9')
            self.assertEqual(response.status_code, 200)
            data = response.json()

            # Verify categories sorted by amount (highest first)
            amounts = [cat['amount'] for cat in data['by_category']]
            self.assertEqual(amounts, sorted(amounts, reverse=True))

    def test_get_monthly_summary_empty_month(self):
        """Test monthly summary for month with no transactions returns zero totals."""
        with self._mock_auth():
            # Get summary for empty month (e.g., 2025-12)
            response = self.client.get('/api/transactions/summary/monthly?year=2025&month=12')
            self.assertEqual(response.status_code, 200)
            data = response.json()

            # Verify zero totals
            self.assertEqual(data['total_amount'], 0)
            self.assertEqual(data['transaction_count'], 0)
            self.assertEqual(len(data['by_category']), 0)

    def test_get_monthly_summary_invalid_month(self):
        """Test monthly summary with invalid month (0, 13) returns 422 validation error."""
        with self._mock_auth():
            # Month too low
            response = self.client.get('/api/transactions/summary/monthly?year=2025&month=0')
            self.assertEqual(response.status_code, 422)

            # Month too high
            response = self.client.get('/api/transactions/summary/monthly?year=2025&month=13')
            self.assertEqual(response.status_code, 422)

    def test_get_monthly_summary_missing_parameters(self):
        """Test monthly summary without required parameters returns 422 error."""
        with self._mock_auth():
            # Missing year and month
            response = self.client.get('/api/transactions/summary/monthly')
            self.assertEqual(response.status_code, 422)

            # Missing month
            response = self.client.get('/api/transactions/summary/monthly?year=2025')
            self.assertEqual(response.status_code, 422)

    def test_get_monthly_summary_unauthorized(self):
        """Test GET /api/transactions/summary/monthly without auth returns 401."""
        # No auth mock - should fail
        response = self.client.get('/api/transactions/summary/monthly?year=2025&month=9')
        self.assertEqual(response.status_code, 401)


if __name__ == '__main__':
    unittest.main()
