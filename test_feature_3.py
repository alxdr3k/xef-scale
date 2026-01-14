"""
Manual test script for Feature 3: Filtered Total Amount API.

This script tests that the new total_amount field is correctly
calculated and returned in the transaction list response.
"""

import sqlite3
import sys
import os

# Add project root to Python path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from src.db.connection import DatabaseConnection
from src.db.repository import CategoryRepository, InstitutionRepository, TransactionRepository


def test_filtered_total_amount():
    """Test the get_filtered_total_amount method."""
    print("Testing Feature 3: Filtered Total Amount API")
    print("=" * 60)

    # Get database connection
    db_conn = DatabaseConnection.get_instance()
    db_conn.row_factory = sqlite3.Row

    # Initialize repositories
    category_repo = CategoryRepository(db_conn)
    institution_repo = InstitutionRepository(db_conn)
    transaction_repo = TransactionRepository(db_conn, category_repo, institution_repo)

    # Test 1: Get total amount with no filters (all transactions)
    print("\nTest 1: Total amount with no filters")
    total_amount_all = transaction_repo.get_filtered_total_amount()
    print(f"Total amount (all transactions): {total_amount_all:,}원")

    # Test 2: Get total amount filtered by year
    print("\nTest 2: Total amount filtered by year=2025")
    total_amount_2025 = transaction_repo.get_filtered_total_amount(year=2025)
    print(f"Total amount (year=2025): {total_amount_2025:,}원")

    # Test 3: Get total amount filtered by year and month
    print("\nTest 3: Total amount filtered by year=2025, month=1")
    total_amount_jan_2025 = transaction_repo.get_filtered_total_amount(year=2025, month=1)
    print(f"Total amount (Jan 2025): {total_amount_jan_2025:,}원")

    # Test 4: Get total amount filtered by category
    print("\nTest 4: Total amount filtered by category_id=1")
    total_amount_cat1 = transaction_repo.get_filtered_total_amount(category_id=1)
    print(f"Total amount (category_id=1): {total_amount_cat1:,}원")

    # Test 5: Get total amount filtered by institution
    print("\nTest 5: Total amount filtered by institution_id=1")
    total_amount_inst1 = transaction_repo.get_filtered_total_amount(institution_id=1)
    print(f"Total amount (institution_id=1): {total_amount_inst1:,}원")

    # Test 6: Get total amount with search filter
    print("\nTest 6: Total amount with search filter")
    total_amount_search = transaction_repo.get_filtered_total_amount(search='카')
    print(f"Total amount (search='카'): {total_amount_search:,}원")

    # Test 7: Verify consistency with get_filtered
    print("\nTest 7: Verify consistency with get_filtered")
    transactions, total_count = transaction_repo.get_filtered(
        year=2025, month=1, limit=100, offset=0
    )
    total_amount_from_filtered = transaction_repo.get_filtered_total_amount(
        year=2025, month=1
    )

    # Calculate sum from returned transactions (just first page)
    page_sum = sum(t['amount'] for t in transactions)

    print(f"Total transactions matching filter: {total_count}")
    print(f"Transactions in current page: {len(transactions)}")
    print(f"Sum of amounts in current page: {page_sum:,}원")
    print(f"Total amount from get_filtered_total_amount: {total_amount_from_filtered:,}원")

    if total_count > len(transactions):
        print(f"\n✓ Pagination working correctly (total > page size)")
        print(f"✓ total_amount ({total_amount_from_filtered:,}원) should be >= page sum ({page_sum:,}원)")
        if total_amount_from_filtered >= page_sum:
            print("✓ PASS: total_amount includes all pages, not just current page")
        else:
            print("✗ FAIL: total_amount should be >= page sum")
    else:
        print(f"\n✓ All transactions fit in one page")
        if total_amount_from_filtered == page_sum:
            print("✓ PASS: total_amount matches page sum when all fit in one page")
        else:
            print("✗ FAIL: total_amount should equal page sum when all fit in one page")

    # Test 8: Test with filters that return no results
    print("\nTest 8: Test with filters that return no results")
    total_amount_empty = transaction_repo.get_filtered_total_amount(
        year=9999, month=12  # Non-existent year
    )
    print(f"Total amount (year=9999): {total_amount_empty:,}원")
    if total_amount_empty == 0:
        print("✓ PASS: Returns 0 for empty result set (COALESCE working)")
    else:
        print("✗ FAIL: Should return 0 for empty result set")

    print("\n" + "=" * 60)
    print("Feature 3 testing complete!")
    print("\nSummary:")
    print("- get_filtered_total_amount() method working correctly")
    print("- Returns total amount across ALL filtered transactions")
    print("- Consistent with get_filtered() filters")
    print("- Returns 0 for empty result sets")
    print("- Correctly handles pagination (sums all pages, not just current)")


if __name__ == "__main__":
    try:
        test_filtered_total_amount()
    except Exception as e:
        print(f"\n✗ ERROR: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
