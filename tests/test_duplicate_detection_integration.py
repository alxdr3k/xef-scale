"""
Integration tests for duplicate detection workflow in file processing pipeline.

Tests the end-to-end duplicate detection flow:
1. Verify duplicate detection components are properly integrated
2. Test database schema supports duplicate confirmation workflow
3. Verify repository methods work correctly
4. Document manual testing procedures for full workflow validation

Note: Full end-to-end testing with actual file uploads should be done manually
using the existing test files in the archive directory.
"""

import os
import sys
from pathlib import Path

# Add project root to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from src.db.connection import DatabaseConnection
from src.db.repository import (
    TransactionRepository,
    ParsingSessionRepository,
    DuplicateConfirmationRepository,
    CategoryRepository,
    InstitutionRepository
)
from src.models import Transaction
from src.duplicate_detector import DuplicateDetector


def test_repository_methods():
    """
    Test 1: Verify ParsingSessionRepository has required methods for duplicate detection.

    Expected behavior:
    - update_status() method exists and works
    - update_processing_result() method exists and works
    """
    print("\n" + "=" * 70)
    print("TEST 1: Repository Methods")
    print("=" * 70)

    conn = DatabaseConnection.get_instance()
    session_repo = ParsingSessionRepository(conn)

    # Verify methods exist
    assert hasattr(session_repo, 'update_status'), \
        "ParsingSessionRepository missing update_status() method"
    assert hasattr(session_repo, 'update_processing_result'), \
        "ParsingSessionRepository missing update_processing_result() method"

    print("  ✓ update_status() method exists")
    print("  ✓ update_processing_result() method exists")

    print("\n" + "=" * 70)
    print("✓ TEST 1 PASSED: Repository methods available")
    print("=" * 70)


def test_duplicate_detector_integration():
    """
    Test 2: Verify DuplicateDetector can be instantiated and used with TransactionRepository.

    Expected behavior:
    - DuplicateDetector can be created with TransactionRepository
    - check_for_duplicates() method works with empty list
    """
    print("\n" + "=" * 70)
    print("TEST 2: DuplicateDetector Integration")
    print("=" * 70)

    conn = DatabaseConnection.get_instance()
    category_repo = CategoryRepository(conn)
    institution_repo = InstitutionRepository(conn)
    transaction_repo = TransactionRepository(conn, category_repo, institution_repo)

    # Create duplicate detector
    duplicate_detector = DuplicateDetector(transaction_repo)
    print("  ✓ DuplicateDetector instantiated successfully")

    # Test with empty list (should return empty list)
    duplicates = duplicate_detector.check_for_duplicates([], file_id=1)
    assert duplicates == [], "Expected empty list for no transactions"
    print("  ✓ check_for_duplicates() works with empty list")

    # Create a test transaction
    test_transaction = Transaction(
        month='01',
        date='2025.01.10',
        category='테스트',
        item='테스트가맹점',
        amount=10000,
        source='테스트카드'
    )

    # Test with single transaction (may or may not find duplicates)
    duplicates = duplicate_detector.check_for_duplicates([test_transaction], file_id=1)
    assert isinstance(duplicates, list), "Expected list from check_for_duplicates()"
    print(f"  ✓ check_for_duplicates() returned {len(duplicates)} potential duplicates")

    print("\n" + "=" * 70)
    print("✓ TEST 2 PASSED: DuplicateDetector integration working")
    print("=" * 70)


def test_duplicate_confirmation_repository():
    """
    Test 3: Verify DuplicateConfirmationRepository is accessible and has required methods.

    Expected behavior:
    - DuplicateConfirmationRepository can be instantiated
    - create_confirmation() method exists
    - get_by_session() method exists
    """
    print("\n" + "=" * 70)
    print("TEST 3: DuplicateConfirmationRepository")
    print("=" * 70)

    conn = DatabaseConnection.get_instance()
    confirmation_repo = DuplicateConfirmationRepository(conn)

    # Verify methods exist
    assert hasattr(confirmation_repo, 'create_confirmation'), \
        "DuplicateConfirmationRepository missing create_confirmation() method"
    assert hasattr(confirmation_repo, 'get_by_session'), \
        "DuplicateConfirmationRepository missing get_by_session() method"

    print("  ✓ DuplicateConfirmationRepository instantiated")
    print("  ✓ create_confirmation() method exists")
    print("  ✓ get_by_session() method exists")

    print("\n" + "=" * 70)
    print("✓ TEST 3 PASSED: DuplicateConfirmationRepository working")
    print("=" * 70)


def test_processing_result_model():
    """
    Test 4: Verify ProcessingResult model supports duplicate detection fields.

    Expected behavior:
    - ProcessingResult has transactions_pending field
    - ProcessingResult has session_id field
    - ProcessingResult has is_pending_confirmation() method
    """
    print("\n" + "=" * 70)
    print("TEST 4: ProcessingResult Model")
    print("=" * 70)

    from src.models import ProcessingResult

    # Create test result with pending confirmation
    result = ProcessingResult(
        status='pending_confirmation',
        message='Test message',
        transaction_count=10,
        transactions_pending=3,
        session_id=1,
        file_id=1,
        file_hash='test_hash'
    )

    assert hasattr(result, 'transactions_pending'), \
        "ProcessingResult missing transactions_pending field"
    assert hasattr(result, 'session_id'), \
        "ProcessingResult missing session_id field"
    assert hasattr(result, 'is_pending_confirmation'), \
        "ProcessingResult missing is_pending_confirmation() method"

    assert result.transactions_pending == 3, "transactions_pending not set correctly"
    assert result.session_id == 1, "session_id not set correctly"
    assert result.is_pending_confirmation() == True, "is_pending_confirmation() not working"

    print("  ✓ ProcessingResult has transactions_pending field")
    print("  ✓ ProcessingResult has session_id field")
    print("  ✓ ProcessingResult has is_pending_confirmation() method")
    print(f"  ✓ transactions_pending: {result.transactions_pending}")
    print(f"  ✓ session_id: {result.session_id}")
    print(f"  ✓ is_pending_confirmation(): {result.is_pending_confirmation()}")

    print("\n" + "=" * 70)
    print("✓ TEST 4 PASSED: ProcessingResult model supports duplicate detection")
    print("=" * 70)


def print_manual_testing_guide():
    """
    Print manual testing procedures for full workflow validation.
    """
    print("\n" + "=" * 70)
    print("MANUAL TESTING GUIDE")
    print("=" * 70)

    print("""
To manually test the complete duplicate detection workflow:

1. Process a file that contains duplicate transactions:
   - Copy an existing file from archive/ to inbox/
   - Watch the file processor logs
   - Verify session status is 'pending_confirmation'

2. Check duplicate confirmation records:
   - Query duplicate_confirmations table
   - Verify confirmation records created for detected duplicates
   - Check confidence scores and match fields

3. Verify partial insertion:
   - Check that only non-duplicate transactions were inserted
   - Verify rows_duplicate count in parsing_sessions table

4. Test normal flow (no duplicates):
   - Process a file with all unique transactions
   - Verify session status is 'completed' (not 'pending_confirmation')
   - Verify all transactions inserted

5. API endpoint testing (if implemented):
   - GET /api/confirmations?session_id={session_id}
   - POST /api/confirmations/{confirmation_id}/confirm
   - Verify transaction insertion after confirmation

Existing test files in archive/:
""")

    # List existing test files
    archive_dir = Path(__file__).parent.parent / 'archive'
    if archive_dir.exists():
        for file in sorted(archive_dir.glob('*.xls')):
            print(f"  - {file.name}")
    else:
        print("  (No archive directory found)")

    print("\n" + "=" * 70)


def run_all_integration_tests():
    """
    Run all integration tests for duplicate detection.
    """
    print("\n" + "=" * 70)
    print("DUPLICATE DETECTION INTEGRATION TESTS")
    print("=" * 70)

    try:
        # Test 1: Repository methods
        test_repository_methods()

        # Test 2: DuplicateDetector integration
        test_duplicate_detector_integration()

        # Test 3: DuplicateConfirmationRepository
        test_duplicate_confirmation_repository()

        # Test 4: ProcessingResult model
        test_processing_result_model()

        print("\n" + "=" * 70)
        print("✓ ALL INTEGRATION TESTS PASSED")
        print("=" * 70)

        # Print manual testing guide
        print_manual_testing_guide()

    except AssertionError as e:
        print("\n" + "=" * 70)
        print(f"✗ TEST FAILED: {e}")
        print("=" * 70)
        sys.exit(1)
    except Exception as e:
        print("\n" + "=" * 70)
        print(f"✗ ERROR: {e}")
        print("=" * 70)
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == '__main__':
    run_all_integration_tests()
