"""
Unit tests for TransactionRepository CRUD methods.

Tests comprehensive coverage of is_editable(), update(), and soft_delete()
methods including edge cases, validation, and error conditions.
"""

import unittest
import sqlite3
from datetime import datetime
from src.db.repository import CategoryRepository, InstitutionRepository, TransactionRepository
from src.models import Transaction


class TestTransactionRepositoryCRUD(unittest.TestCase):
    """
    Unit tests for TransactionRepository CRUD operations.

    Tests is_editable(), update(), and soft_delete() methods with comprehensive
    coverage of happy paths, edge cases, and error conditions.
    """

    def setUp(self):
        """Set up each test with fresh in-memory database and test data."""
        # Create in-memory database connection
        self.conn = sqlite3.connect(':memory:')
        self.conn.row_factory = sqlite3.Row
        self.conn.execute('PRAGMA foreign_keys=ON')

        # Create schema from migrations
        migrations = [
            'db/migrations/001_create_schema.sql',
            'db/migrations/002_seed_initial_data.sql',
            'db/migrations/004_add_file_tracking.sql',
            'db/migrations/009_add_soft_delete.sql'
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

    def tearDown(self):
        """Clean up after each test."""
        if hasattr(self, 'conn'):
            self.conn.close()

    def _create_test_data(self):
        """
        Create test transactions for CRUD operations.

        Creates:
        - Manual transactions (file_id IS NULL) for edit/delete testing
        - Parsed transactions (file_id NOT NULL) for immutability testing
        - Deleted transactions for soft delete testing
        """
        # Insert test file for parsed transactions
        cursor = self.conn.execute('''
            INSERT INTO processed_files (file_name, file_path, file_hash, file_size, institution_id)
            VALUES ('test_statement.xlsx', '/inbox/test_statement.xlsx', 'abc123', 1024, 1)
        ''')
        self.test_file_id = cursor.lastrowid

        # Manual transactions (editable)
        manual_transactions = [
            Transaction('01', '2026.01.05', '식비', '스타벅스', 5000, '하나카드'),
            Transaction('01', '2026.01.10', '교통', '카카오택시', 15000, '신한카드'),
            Transaction('01', '2026.01.15', '통신', 'SKT', 50000, '토스뱅크'),
        ]
        self.transaction_repo.batch_insert(manual_transactions)
        self.conn.commit()

        # Get manual transaction IDs
        cursor = self.conn.execute(
            'SELECT id FROM transactions WHERE file_id IS NULL ORDER BY id'
        )
        manual_ids = [row['id'] for row in cursor.fetchall()]
        self.manual_txn_id = manual_ids[0]
        self.manual_txn_id_2 = manual_ids[1]
        self.manual_txn_id_3 = manual_ids[2]

        # Parsed transaction (not editable - has file_id)
        cursor = self.conn.execute('''
            INSERT INTO transactions (
                transaction_date, transaction_year, transaction_month,
                merchant_name, amount, category_id, institution_id, file_id, row_number_in_file
            )
            VALUES ('2026.01.20', 2026, 1, '파리바게뜨', 8000, 1, 1, ?, 1)
        ''', (self.test_file_id,))
        self.parsed_txn_id = cursor.lastrowid

        # Already deleted transaction
        cursor = self.conn.execute('''
            INSERT INTO transactions (
                transaction_date, transaction_year, transaction_month,
                merchant_name, amount, category_id, institution_id, deleted_at
            )
            VALUES ('2026.01.25', 2026, 1, '올리브영', 23000, 1, 1, CURRENT_TIMESTAMP)
        ''')
        self.deleted_txn_id = cursor.lastrowid

        # Transaction with both deleted_at AND file_id (for edge case testing)
        cursor = self.conn.execute('''
            INSERT INTO transactions (
                transaction_date, transaction_year, transaction_month,
                merchant_name, amount, category_id, institution_id,
                file_id, row_number_in_file, deleted_at
            )
            VALUES ('2026.01.28', 2026, 1, 'CU편의점', 3000, 1, 1, ?, 2, CURRENT_TIMESTAMP)
        ''', (self.test_file_id,))
        self.deleted_parsed_txn_id = cursor.lastrowid

        self.conn.commit()

    # ==================== is_editable() Tests ====================

    def test_is_editable_manual_transaction(self):
        """Manual transaction (file_id IS NULL) should be editable."""
        result = self.transaction_repo.is_editable(self.manual_txn_id)
        self.assertTrue(result)

    def test_is_editable_parsed_transaction(self):
        """Parsed transaction (file_id NOT NULL) should not be editable."""
        result = self.transaction_repo.is_editable(self.parsed_txn_id)
        self.assertFalse(result)

    def test_is_editable_deleted_transaction(self):
        """Deleted transaction should not be editable."""
        result = self.transaction_repo.is_editable(self.deleted_txn_id)
        self.assertFalse(result)

    def test_is_editable_nonexistent_transaction(self):
        """Non-existent transaction ID should return False."""
        result = self.transaction_repo.is_editable(99999)
        self.assertFalse(result)

    def test_is_editable_deleted_and_parsed(self):
        """Transaction with both deleted_at AND file_id should not be editable."""
        result = self.transaction_repo.is_editable(self.deleted_parsed_txn_id)
        self.assertFalse(result)

    # ==================== update() Tests ====================

    def test_update_single_field(self):
        """Update only amount field should succeed."""
        result = self.transaction_repo.update(self.manual_txn_id, {'amount': 10000})
        self.assertTrue(result)

        # Verify update
        txn = self.transaction_repo.get_by_id(self.manual_txn_id)
        self.assertIsNotNone(txn)
        self.assertEqual(txn['amount'], 10000)

    def test_update_multiple_fields(self):
        """Update multiple fields at once should succeed."""
        updates = {
            'merchant_name': '스타벅스 강남점',
            'amount': 5500,
            'category': '식비'
        }
        result = self.transaction_repo.update(self.manual_txn_id, updates)
        self.assertTrue(result)

        # Verify all updates
        txn = self.transaction_repo.get_by_id(self.manual_txn_id)
        self.assertIsNotNone(txn)
        self.assertEqual(txn['merchant_name'], '스타벅스 강남점')
        self.assertEqual(txn['amount'], 5500)
        self.assertEqual(txn['category_name'], '식비')

    def test_update_date_parsing(self):
        """Date change should auto-extract transaction_year and transaction_month."""
        result = self.transaction_repo.update(
            self.manual_txn_id,
            {'transaction_date': '2025.12.25'}
        )
        self.assertTrue(result)

        # Verify date fields (note: database stores in YYYY-MM-DD format)
        txn = self.transaction_repo.get_by_id(self.manual_txn_id)
        self.assertIsNotNone(txn)
        self.assertEqual(txn['transaction_date'], '2025-12-25')
        self.assertEqual(txn['transaction_year'], 2025)
        self.assertEqual(txn['transaction_month'], 12)

    def test_update_category_by_name(self):
        """Category name should auto-convert to category_id."""
        # Update to existing category
        result = self.transaction_repo.update(self.manual_txn_id, {'category': '교통'})
        self.assertTrue(result)

        # Verify category changed
        txn = self.transaction_repo.get_by_id(self.manual_txn_id)
        self.assertIsNotNone(txn)
        self.assertEqual(txn['category_name'], '교통')

        # Update to new category (should auto-create)
        result = self.transaction_repo.update(self.manual_txn_id, {'category': '의료'})
        self.assertTrue(result)

        txn = self.transaction_repo.get_by_id(self.manual_txn_id)
        self.assertIsNotNone(txn)
        self.assertEqual(txn['category_name'], '의료')

    def test_update_institution_by_name(self):
        """Institution name should auto-convert to institution_id."""
        # Test using 'source' field
        result = self.transaction_repo.update(self.manual_txn_id, {'source': '토스뱅크'})
        self.assertTrue(result)

        txn = self.transaction_repo.get_by_id(self.manual_txn_id)
        self.assertIsNotNone(txn)
        self.assertEqual(txn['institution_name'], '토스뱅크')

        # Test using 'institution' field (alternative name)
        result = self.transaction_repo.update(self.manual_txn_id, {'institution': '신한카드'})
        self.assertTrue(result)

        txn = self.transaction_repo.get_by_id(self.manual_txn_id)
        self.assertIsNotNone(txn)
        self.assertEqual(txn['institution_name'], '신한카드')

    def test_update_parsed_transaction_error(self):
        """Updating parsed transaction should raise ValueError."""
        with self.assertRaises(ValueError) as context:
            self.transaction_repo.update(self.parsed_txn_id, {'amount': 10000})

        self.assertIn('not editable', str(context.exception))

    def test_update_deleted_transaction(self):
        """Updating deleted transaction should raise ValueError."""
        with self.assertRaises(ValueError) as context:
            self.transaction_repo.update(self.deleted_txn_id, {'amount': 10000})

        self.assertIn('not editable', str(context.exception))

    def test_update_protected_fields_ignored(self):
        """Protected fields (id, file_id, created_at) should raise ValueError."""
        # Test id field
        with self.assertRaises(ValueError) as context:
            self.transaction_repo.update(self.manual_txn_id, {'id': 99999})
        self.assertIn('protected fields', str(context.exception))

        # Test file_id field
        with self.assertRaises(ValueError) as context:
            self.transaction_repo.update(self.manual_txn_id, {'file_id': 99})
        self.assertIn('protected fields', str(context.exception))

        # Test created_at field
        with self.assertRaises(ValueError) as context:
            self.transaction_repo.update(
                self.manual_txn_id,
                {'created_at': '2020.01.01'}
            )
        self.assertIn('protected fields', str(context.exception))

        # Test updated_at field
        with self.assertRaises(ValueError) as context:
            self.transaction_repo.update(
                self.manual_txn_id,
                {'updated_at': '2020.01.01'}
            )
        self.assertIn('protected fields', str(context.exception))

        # Test row_number_in_file field
        with self.assertRaises(ValueError) as context:
            self.transaction_repo.update(
                self.manual_txn_id,
                {'row_number_in_file': 999}
            )
        self.assertIn('protected fields', str(context.exception))

    def test_update_nonexistent_transaction(self):
        """Non-existent transaction ID should raise ValueError (not editable)."""
        # Non-existent transactions are treated as not editable, raising ValueError
        with self.assertRaises(ValueError) as context:
            self.transaction_repo.update(99999, {'amount': 10000})
        self.assertIn('not editable', str(context.exception))

    def test_update_empty_updates(self):
        """Empty updates dict should return False (no changes)."""
        result = self.transaction_repo.update(self.manual_txn_id, {})
        self.assertFalse(result)

    def test_update_with_validation_bypass(self):
        """validate_editable=False should allow parsed transaction update."""
        # Without bypass, should fail
        with self.assertRaises(ValueError):
            self.transaction_repo.update(self.parsed_txn_id, {'amount': 12000})

        # With bypass, should succeed
        result = self.transaction_repo.update(
            self.parsed_txn_id,
            {'amount': 12000},
            validate_editable=False
        )
        self.assertTrue(result)

        # Verify update
        txn = self.transaction_repo.get_by_id(self.parsed_txn_id)
        self.assertIsNotNone(txn)
        self.assertEqual(txn['amount'], 12000)

    def test_update_updates_updated_at(self):
        """updated_at timestamp should be auto-updated on update."""
        # Get initial updated_at
        txn_before = self.transaction_repo.get_by_id(self.manual_txn_id)
        updated_at_before = txn_before['updated_at'] if 'updated_at' in txn_before else None

        # Sleep for 1 second to ensure timestamp differs (SQLite CURRENT_TIMESTAMP has 1-second precision)
        import time
        time.sleep(1.1)

        # Update transaction
        self.transaction_repo.update(self.manual_txn_id, {'amount': 7000})

        # Get updated transaction
        txn_after = self.transaction_repo.get_by_id(self.manual_txn_id)
        updated_at_after = txn_after.get('updated_at')

        # Verify updated_at was set and is different
        self.assertIsNotNone(updated_at_after)
        if updated_at_before is not None:
            self.assertNotEqual(updated_at_before, updated_at_after)

    # ==================== soft_delete() Tests ====================

    def test_soft_delete_manual_transaction(self):
        """Soft delete manual transaction should set deleted_at timestamp."""
        result = self.transaction_repo.soft_delete(self.manual_txn_id)
        self.assertTrue(result)

        # Verify transaction is deleted (not returned by get_by_id)
        txn = self.transaction_repo.get_by_id(self.manual_txn_id)
        self.assertIsNone(txn)

    def test_soft_delete_parsed_transaction_error(self):
        """Deleting parsed transaction should raise ValueError."""
        with self.assertRaises(ValueError) as context:
            self.transaction_repo.soft_delete(self.parsed_txn_id)

        self.assertIn('not editable', str(context.exception))

    def test_soft_delete_already_deleted(self):
        """Re-deleting already deleted transaction should raise ValueError."""
        # First delete should succeed
        result = self.transaction_repo.soft_delete(self.manual_txn_id)
        self.assertTrue(result)

        # Second delete should fail (transaction already deleted)
        with self.assertRaises(ValueError):
            self.transaction_repo.soft_delete(self.manual_txn_id)

    def test_soft_delete_nonexistent_transaction(self):
        """Non-existent transaction ID should return False (not found)."""
        result = self.transaction_repo.soft_delete(99999, validate_editable=False)
        self.assertFalse(result)

    def test_soft_delete_preserves_data(self):
        """Soft delete should preserve row data, only setting deleted_at."""
        # Get original data
        txn_before = self.transaction_repo.get_by_id(self.manual_txn_id)
        original_merchant = txn_before['merchant_name']
        original_amount = txn_before['amount']

        # Soft delete
        self.transaction_repo.soft_delete(self.manual_txn_id)

        # Verify row still exists in database (bypass deleted_at filter)
        cursor = self.conn.execute(
            'SELECT * FROM transactions WHERE id = ?',
            (self.manual_txn_id,)
        )
        row = cursor.fetchone()
        self.assertIsNotNone(row)

        # Verify data preserved
        self.assertEqual(row['merchant_name'], original_merchant)
        self.assertEqual(row['amount'], original_amount)
        self.assertIsNotNone(row['deleted_at'])

    def test_soft_delete_with_validation_bypass(self):
        """validate_editable=False should allow parsed transaction deletion."""
        # Without bypass, should fail
        with self.assertRaises(ValueError):
            self.transaction_repo.soft_delete(self.parsed_txn_id)

        # With bypass, should succeed
        result = self.transaction_repo.soft_delete(
            self.parsed_txn_id,
            validate_editable=False
        )
        self.assertTrue(result)

        # Verify deletion
        txn = self.transaction_repo.get_by_id(self.parsed_txn_id)
        self.assertIsNone(txn)

    def test_soft_delete_excludes_from_queries(self):
        """Deleted transactions should not appear in get_filtered() results."""
        # Get initial count
        txns_before, count_before = self.transaction_repo.get_filtered()
        self.assertGreater(count_before, 0)

        # Soft delete a manual transaction
        self.transaction_repo.soft_delete(self.manual_txn_id)

        # Get updated count
        txns_after, count_after = self.transaction_repo.get_filtered()

        # Verify count decreased by 1
        self.assertEqual(count_after, count_before - 1)

        # Verify deleted transaction not in results
        deleted_ids = [txn['id'] for txn in txns_after if txn['id'] == self.manual_txn_id]
        self.assertEqual(len(deleted_ids), 0)


    # ==================== update_notes() Tests ====================

    def test_update_notes_manual_transaction(self):
        """Test updating notes for manual transaction."""
        notes_text = "회의 중 커피 구매"

        result = self.transaction_repo.update_notes(self.manual_txn_id, notes_text)

        self.assertTrue(result)

        # Verify notes were persisted
        txn = self.transaction_repo.get_by_id(self.manual_txn_id)
        self.assertEqual(txn['notes'], notes_text)

    def test_update_notes_parsed_transaction(self):
        """Test updating notes for parsed transaction (should succeed)."""
        notes_text = "자동 파싱된 거래에 메모 추가"

        result = self.transaction_repo.update_notes(self.parsed_txn_id, notes_text)

        self.assertTrue(result)

        # Verify notes were persisted for parsed transaction
        txn = self.transaction_repo.get_by_id(self.parsed_txn_id)
        self.assertEqual(txn['notes'], notes_text)

    def test_update_notes_clear_notes(self):
        """Test clearing notes by setting to None."""
        # First add notes
        self.transaction_repo.update_notes(self.manual_txn_id, "Original notes")

        # Then clear notes
        result = self.transaction_repo.update_notes(self.manual_txn_id, None)

        self.assertTrue(result)

        # Verify notes were cleared
        txn = self.transaction_repo.get_by_id(self.manual_txn_id)
        self.assertIsNone(txn['notes'])

    def test_update_notes_empty_string(self):
        """Test setting notes to empty string."""
        result = self.transaction_repo.update_notes(self.manual_txn_id, "")

        self.assertTrue(result)

        # Verify empty string was stored
        txn = self.transaction_repo.get_by_id(self.manual_txn_id)
        self.assertEqual(txn['notes'], "")

    def test_update_notes_nonexistent_transaction(self):
        """Test updating notes for non-existent transaction returns False."""
        result = self.transaction_repo.update_notes(999999, "Test notes")

        self.assertFalse(result)

    def test_update_notes_deleted_transaction(self):
        """Test updating notes for soft-deleted transaction returns False."""
        # Soft delete transaction
        self.transaction_repo.soft_delete(self.manual_txn_id)

        # Attempt to update notes
        result = self.transaction_repo.update_notes(self.manual_txn_id, "Should fail")

        self.assertFalse(result)

    def test_update_notes_updates_timestamp(self):
        """Test that updating notes also updates updated_at timestamp."""
        # Get original updated_at
        txn_before = self.transaction_repo.get_by_id(self.manual_txn_id)
        updated_at_before = txn_before['updated_at']

        # Small delay to ensure timestamp difference
        import time
        time.sleep(0.1)

        # Update notes
        self.transaction_repo.update_notes(self.manual_txn_id, "Updated notes")

        # Get updated updated_at
        txn_after = self.transaction_repo.get_by_id(self.manual_txn_id)
        updated_at_after = txn_after['updated_at']

        # Verify timestamp changed
        self.assertNotEqual(updated_at_before, updated_at_after)

    def test_update_notes_preserves_other_fields(self):
        """Test that updating notes doesn't affect other transaction fields."""
        # Get original transaction data
        txn_before = self.transaction_repo.get_by_id(self.manual_txn_id)
        original_merchant = txn_before['merchant_name']
        original_amount = txn_before['amount']
        original_category = txn_before['category_id']

        # Update notes
        self.transaction_repo.update_notes(self.manual_txn_id, "Test preservation")

        # Verify other fields unchanged
        txn_after = self.transaction_repo.get_by_id(self.manual_txn_id)
        self.assertEqual(txn_after['merchant_name'], original_merchant)
        self.assertEqual(txn_after['amount'], original_amount)
        self.assertEqual(txn_after['category_id'], original_category)
        self.assertEqual(txn_after['notes'], "Test preservation")

    def test_update_notes_long_text(self):
        """Test updating notes with long text (up to 500 chars)."""
        long_notes = "A" * 500  # 500 character string

        result = self.transaction_repo.update_notes(self.manual_txn_id, long_notes)

        self.assertTrue(result)

        # Verify long notes were stored
        txn = self.transaction_repo.get_by_id(self.manual_txn_id)
        self.assertEqual(txn['notes'], long_notes)
        self.assertEqual(len(txn['notes']), 500)


if __name__ == '__main__':
    unittest.main()
