"""
Unit tests for DuplicateDetector service.

Tests duplicate detection logic including:
- Exact match detection (100% confidence)
- Cross-institution duplicate detection (80% confidence)
- Edge cases (null installments, special characters)
- Batch processing
- Summary statistics
"""

import unittest
import os
import tempfile
import shutil
import sqlite3
from datetime import datetime

from src.duplicate_detector import DuplicateDetector, DuplicateMatch
from src.models import Transaction
from src.db.connection import DatabaseConnection
from src.db.repository import CategoryRepository, InstitutionRepository, TransactionRepository
from src.config import DIRECTORIES


class TestDuplicateDetector(unittest.TestCase):
    """
    Unit tests for DuplicateDetector service.

    Creates temporary database for each test to avoid polluting production data.
    Tests comprehensive duplicate detection scenarios including exact matches,
    cross-institution duplicates, and edge cases.
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

        # Execute seed data migration (includes default categories and institutions)
        with open('db/migrations/002_seed_initial_data.sql', 'r', encoding='utf-8') as f:
            conn.executescript(f.read())

        # Execute file tracking migration (required for duplicate detection)
        with open('db/migrations/004_add_file_tracking.sql', 'r', encoding='utf-8') as f:
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

        # Initialize detector
        self.detector = DuplicateDetector(self.transaction_repo)

    def tearDown(self):
        """Clean up after each test."""
        # Close connection
        DatabaseConnection.close()

    def test_exact_match_detection(self):
        """Test detection of exact match (100% confidence)."""
        # Insert existing transaction
        existing_txn = Transaction(
            month='09',
            date='2025.09.13',
            category='카페/간식',
            item='스타벅스',
            amount=5000,
            source='하나카드'
        )
        txn_id = self.transaction_repo.insert(existing_txn)
        self.assertGreater(txn_id, 0)

        # Create new transaction with same data
        new_txn = Transaction(
            month='09',
            date='2025.09.13',
            category='카페/간식',
            item='스타벅스',
            amount=5000,
            source='하나카드'
        )

        # Check for duplicates
        duplicates = self.detector.check_for_duplicates([new_txn], file_id=1)

        # Assert
        self.assertEqual(len(duplicates), 1)
        match = duplicates[0]
        self.assertEqual(match.confidence_score, 100)
        self.assertTrue(match.is_exact_match())
        self.assertEqual(match.existing_transaction_id, txn_id)
        self.assertEqual(match.new_transaction_index, 1)
        self.assertIn('date', match.match_fields)
        self.assertIn('institution', match.match_fields)
        self.assertIn('merchant', match.match_fields)
        self.assertIn('amount', match.match_fields)
        self.assertEqual(match.difference_summary, 'Exact match')

    def test_cross_institution_duplicate(self):
        """Test detection of cross-institution duplicate (80% confidence)."""
        # Insert existing transaction from 하나카드
        existing_txn = Transaction(
            month='09',
            date='2025.09.13',
            category='카페/간식',
            item='스타벅스',
            amount=5000,
            source='하나카드'
        )
        txn_id = self.transaction_repo.insert(existing_txn)
        self.assertGreater(txn_id, 0)

        # Create new transaction from 신한카드 (different institution, same merchant/amount/date)
        new_txn = Transaction(
            month='09',
            date='2025.09.13',
            category='카페/간식',
            item='스타벅스',
            amount=5000,
            source='신한카드'
        )

        # Check for duplicates
        duplicates = self.detector.check_for_duplicates([new_txn], file_id=1)

        # Assert
        self.assertEqual(len(duplicates), 1)
        match = duplicates[0]
        self.assertEqual(match.confidence_score, 80)
        self.assertTrue(match.is_cross_institution_match())
        self.assertEqual(match.existing_transaction_id, txn_id)
        self.assertIn('date', match.match_fields)
        self.assertIn('merchant', match.match_fields)
        self.assertIn('amount', match.match_fields)
        self.assertIn('Different institution', match.difference_summary)
        self.assertIn('하나카드', match.difference_summary)
        self.assertIn('신한카드', match.difference_summary)

    def test_no_match_different_date(self):
        """Test no match when date is different."""
        # Insert existing transaction
        existing_txn = Transaction(
            month='09',
            date='2025.09.13',
            category='카페/간식',
            item='스타벅스',
            amount=5000,
            source='하나카드'
        )
        self.transaction_repo.insert(existing_txn)

        # Create new transaction with different date
        new_txn = Transaction(
            month='09',
            date='2025.09.14',  # Different date
            category='카페/간식',
            item='스타벅스',
            amount=5000,
            source='하나카드'
        )

        # Check for duplicates
        duplicates = self.detector.check_for_duplicates([new_txn], file_id=1)

        # Assert - no duplicates found
        self.assertEqual(len(duplicates), 0)

    def test_no_match_different_amount(self):
        """Test no match when amount is different."""
        # Insert existing transaction
        existing_txn = Transaction(
            month='09',
            date='2025.09.13',
            category='카페/간식',
            item='스타벅스',
            amount=5000,
            source='하나카드'
        )
        self.transaction_repo.insert(existing_txn)

        # Create new transaction with different amount
        new_txn = Transaction(
            month='09',
            date='2025.09.13',
            category='카페/간식',
            item='스타벅스',
            amount=6000,  # Different amount
            source='하나카드'
        )

        # Check for duplicates
        duplicates = self.detector.check_for_duplicates([new_txn], file_id=1)

        # Assert - no duplicates found
        self.assertEqual(len(duplicates), 0)

    def test_no_match_different_merchant(self):
        """Test no match when merchant is different."""
        # Insert existing transaction
        existing_txn = Transaction(
            month='09',
            date='2025.09.13',
            category='카페/간식',
            item='스타벅스',
            amount=5000,
            source='하나카드'
        )
        self.transaction_repo.insert(existing_txn)

        # Create new transaction with different merchant
        new_txn = Transaction(
            month='09',
            date='2025.09.13',
            category='카페/간식',
            item='블루보틀',  # Different merchant
            amount=5000,
            source='하나카드'
        )

        # Check for duplicates
        duplicates = self.detector.check_for_duplicates([new_txn], file_id=1)

        # Assert - no duplicates found
        self.assertEqual(len(duplicates), 0)

    def test_exact_match_with_installment(self):
        """Test exact match detection with installment transactions."""
        # Insert existing installment transaction
        existing_txn = Transaction(
            month='09',
            date='2025.09.13',
            category='전자제품',
            item='애플스토어',
            amount=100000,
            source='하나카드',
            installment_months=12,
            installment_current=1,
            original_amount=1200000
        )
        txn_id = self.transaction_repo.insert(existing_txn)
        self.assertGreater(txn_id, 0)

        # Create new transaction with same installment data
        new_txn = Transaction(
            month='09',
            date='2025.09.13',
            category='전자제품',
            item='애플스토어',
            amount=100000,
            source='하나카드',
            installment_months=12,
            installment_current=1,
            original_amount=1200000
        )

        # Check for duplicates
        duplicates = self.detector.check_for_duplicates([new_txn], file_id=1)

        # Assert
        self.assertEqual(len(duplicates), 1)
        match = duplicates[0]
        self.assertEqual(match.confidence_score, 100)
        self.assertTrue(match.is_exact_match())

    def test_no_match_different_installment_number(self):
        """Test no match when installment number differs."""
        # Insert existing installment transaction (month 1)
        existing_txn = Transaction(
            month='09',
            date='2025.09.13',
            category='전자제품',
            item='애플스토어',
            amount=100000,
            source='하나카드',
            installment_months=12,
            installment_current=1,
            original_amount=1200000
        )
        self.transaction_repo.insert(existing_txn)

        # Create new transaction with different installment number (month 2)
        new_txn = Transaction(
            month='10',
            date='2025.10.13',
            category='전자제품',
            item='애플스토어',
            amount=100000,
            source='하나카드',
            installment_months=12,
            installment_current=2,  # Different installment
            original_amount=1200000
        )

        # Check for duplicates
        duplicates = self.detector.check_for_duplicates([new_txn], file_id=1)

        # Assert - no duplicates (different installment number)
        self.assertEqual(len(duplicates), 0)

    def test_cross_institution_with_installment(self):
        """Test cross-institution duplicate with installment transactions."""
        # Insert existing installment transaction from 하나카드
        existing_txn = Transaction(
            month='09',
            date='2025.09.13',
            category='전자제품',
            item='애플스토어',
            amount=100000,
            source='하나카드',
            installment_months=12,
            installment_current=1,
            original_amount=1200000
        )
        txn_id = self.transaction_repo.insert(existing_txn)

        # Create new transaction from 신한카드 with same installment data
        new_txn = Transaction(
            month='09',
            date='2025.09.13',
            category='전자제품',
            item='애플스토어',
            amount=100000,
            source='신한카드',  # Different institution
            installment_months=12,
            installment_current=1,
            original_amount=1200000
        )

        # Check for duplicates
        duplicates = self.detector.check_for_duplicates([new_txn], file_id=1)

        # Assert - cross-institution duplicate
        self.assertEqual(len(duplicates), 1)
        match = duplicates[0]
        self.assertEqual(match.confidence_score, 80)
        self.assertTrue(match.is_cross_institution_match())

    def test_null_installment_match(self):
        """Test exact match with null installment fields."""
        # Insert existing one-time transaction (no installment)
        existing_txn = Transaction(
            month='09',
            date='2025.09.13',
            category='카페/간식',
            item='스타벅스',
            amount=5000,
            source='하나카드',
            installment_months=None,
            installment_current=None,
            original_amount=None
        )
        txn_id = self.transaction_repo.insert(existing_txn)

        # Create new transaction with null installments
        new_txn = Transaction(
            month='09',
            date='2025.09.13',
            category='카페/간식',
            item='스타벅스',
            amount=5000,
            source='하나카드',
            installment_months=None,
            installment_current=None,
            original_amount=None
        )

        # Check for duplicates
        duplicates = self.detector.check_for_duplicates([new_txn], file_id=1)

        # Assert - exact match
        self.assertEqual(len(duplicates), 1)
        match = duplicates[0]
        self.assertEqual(match.confidence_score, 100)
        self.assertTrue(match.is_exact_match())

    def test_special_characters_in_merchant_name(self):
        """Test duplicate detection with special characters in merchant names."""
        # Insert existing transaction with special characters
        existing_txn = Transaction(
            month='09',
            date='2025.09.13',
            category='식비',
            item='맥도날드(McDonald\'s)',  # Special characters
            amount=8000,
            source='하나카드'
        )
        txn_id = self.transaction_repo.insert(existing_txn)

        # Create new transaction with same special characters
        new_txn = Transaction(
            month='09',
            date='2025.09.13',
            category='식비',
            item='맥도날드(McDonald\'s)',
            amount=8000,
            source='하나카드'
        )

        # Check for duplicates
        duplicates = self.detector.check_for_duplicates([new_txn], file_id=1)

        # Assert - exact match
        self.assertEqual(len(duplicates), 1)
        match = duplicates[0]
        self.assertEqual(match.confidence_score, 100)
        self.assertTrue(match.is_exact_match())

    def test_batch_processing_multiple_duplicates(self):
        """Test batch processing with multiple duplicate matches."""
        # Insert existing transactions
        txn1 = Transaction(
            month='09',
            date='2025.09.13',
            category='카페/간식',
            item='스타벅스',
            amount=5000,
            source='하나카드'
        )
        txn2 = Transaction(
            month='09',
            date='2025.09.14',
            category='식비',
            item='맥도날드',
            amount=8000,
            source='신한카드'
        )
        txn_id1 = self.transaction_repo.insert(txn1)
        txn_id2 = self.transaction_repo.insert(txn2)

        # Create batch with duplicates and new transactions
        new_transactions = [
            Transaction(  # Duplicate of txn1 (exact match)
                month='09',
                date='2025.09.13',
                category='카페/간식',
                item='스타벅스',
                amount=5000,
                source='하나카드'
            ),
            Transaction(  # New transaction (no duplicate)
                month='09',
                date='2025.09.15',
                category='교통',
                item='서울교통공사',
                amount=1250,
                source='하나카드'
            ),
            Transaction(  # Duplicate of txn2 (cross-institution)
                month='09',
                date='2025.09.14',
                category='식비',
                item='맥도날드',
                amount=8000,
                source='하나카드'  # Different institution
            ),
            Transaction(  # New transaction (no duplicate)
                month='09',
                date='2025.09.16',
                category='편의점/마트',
                item='GS25',
                amount=3000,
                source='하나카드'
            )
        ]

        # Check for duplicates
        duplicates = self.detector.check_for_duplicates(new_transactions, file_id=1)

        # Assert - 2 duplicates found (index 1 and 3)
        self.assertEqual(len(duplicates), 2)

        # Find exact match
        exact_matches = [d for d in duplicates if d.is_exact_match()]
        self.assertEqual(len(exact_matches), 1)
        self.assertEqual(exact_matches[0].new_transaction_index, 1)

        # Find cross-institution match
        cross_matches = [d for d in duplicates if d.is_cross_institution_match()]
        self.assertEqual(len(cross_matches), 1)
        self.assertEqual(cross_matches[0].new_transaction_index, 3)

    def test_empty_transaction_list(self):
        """Test handling of empty transaction list."""
        duplicates = self.detector.check_for_duplicates([], file_id=1)

        # Assert - no duplicates
        self.assertEqual(len(duplicates), 0)

    def test_no_duplicates_in_database(self):
        """Test processing transactions when database is empty."""
        # Create new transactions (no existing data in DB)
        new_transactions = [
            Transaction(
                month='09',
                date='2025.09.13',
                category='카페/간식',
                item='스타벅스',
                amount=5000,
                source='하나카드'
            ),
            Transaction(
                month='09',
                date='2025.09.14',
                category='식비',
                item='맥도날드',
                amount=8000,
                source='하나카드'
            )
        ]

        # Check for duplicates
        duplicates = self.detector.check_for_duplicates(new_transactions, file_id=1)

        # Assert - no duplicates
        self.assertEqual(len(duplicates), 0)

    def test_get_match_summary(self):
        """Test summary statistics generation."""
        # Insert existing transactions
        txn1 = Transaction(
            month='09',
            date='2025.09.13',
            category='카페/간식',
            item='스타벅스',
            amount=5000,
            source='하나카드'
        )
        txn2 = Transaction(
            month='09',
            date='2025.09.14',
            category='식비',
            item='맥도날드',
            amount=8000,
            source='신한카드'
        )
        self.transaction_repo.insert(txn1)
        self.transaction_repo.insert(txn2)

        # Create batch with duplicates
        new_transactions = [
            Transaction(  # Exact match
                month='09',
                date='2025.09.13',
                category='카페/간식',
                item='스타벅스',
                amount=5000,
                source='하나카드'
            ),
            Transaction(  # New transaction
                month='09',
                date='2025.09.15',
                category='교통',
                item='서울교통공사',
                amount=1250,
                source='하나카드'
            ),
            Transaction(  # Cross-institution
                month='09',
                date='2025.09.14',
                category='식비',
                item='맥도날드',
                amount=8000,
                source='하나카드'
            )
        ]

        # Check for duplicates
        duplicates = self.detector.check_for_duplicates(new_transactions, file_id=1)

        # Get summary
        summary = self.detector.get_match_summary(duplicates)

        # Assert
        self.assertEqual(summary['total'], 2)
        self.assertEqual(summary['exact_matches'], 1)
        self.assertEqual(summary['cross_institution_matches'], 1)
        self.assertEqual(summary['affected_rows'], [1, 3])

    def test_duplicate_match_to_dict(self):
        """Test DuplicateMatch.to_dict() serialization."""
        # Create a transaction
        txn = Transaction(
            month='09',
            date='2025.09.13',
            category='카페/간식',
            item='스타벅스',
            amount=5000,
            source='하나카드'
        )

        # Create a mock existing transaction dict
        existing_txn = {
            'id': 123,
            'transaction_date': '2025-09-13',
            'merchant_name': '스타벅스',
            'amount': 5000,
            'institution_name': '하나카드'
        }

        # Create DuplicateMatch
        match = DuplicateMatch(
            new_transaction=txn,
            new_transaction_index=1,
            existing_transaction_id=123,
            existing_transaction=existing_txn,
            confidence_score=100,
            match_fields=['date', 'institution', 'merchant', 'amount'],
            difference_summary='Exact match'
        )

        # Convert to dict
        match_dict = match.to_dict()

        # Assert
        self.assertEqual(match_dict['new_transaction_index'], 1)
        self.assertEqual(match_dict['existing_transaction_id'], 123)
        self.assertEqual(match_dict['confidence_score'], 100)
        self.assertEqual(match_dict['match_fields'], ['date', 'institution', 'merchant', 'amount'])
        self.assertEqual(match_dict['difference_summary'], 'Exact match')
        self.assertIsInstance(match_dict['new_transaction'], dict)
        self.assertIsInstance(match_dict['existing_transaction'], dict)

    def test_duplicate_match_str_representation(self):
        """Test DuplicateMatch.__str__() representation."""
        txn = Transaction(
            month='09',
            date='2025.09.13',
            category='카페/간식',
            item='스타벅스',
            amount=5000,
            source='하나카드'
        )

        match = DuplicateMatch(
            new_transaction=txn,
            new_transaction_index=1,
            existing_transaction_id=123,
            existing_transaction={'id': 123},
            confidence_score=100,
            match_fields=['date', 'merchant'],
            difference_summary='Exact match'
        )

        # Convert to string
        str_repr = str(match)

        # Assert - check key components are in string
        self.assertIn('DuplicateMatch', str_repr)
        self.assertIn('confidence=100%', str_repr)
        self.assertIn('existing_id=123', str_repr)


if __name__ == '__main__':
    unittest.main()
