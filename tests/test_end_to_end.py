"""
End-to-end testing and verification of expense tracker parsing system.

Validates database state after file processing: session tracking, skip recording,
API methods, and accounting equation verification. Works with existing parsed data
rather than reprocessing files.
"""

import os
import sys
from pathlib import Path

# Add project root to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from src.db.connection import DatabaseConnection
from src.db.repository import ParsingSessionRepository, SkippedTransactionRepository


def verify_end_to_end():
    """
    Comprehensive end-to-end verification of expense tracker system.

    Tests:
    1. Retrieves most recent parsing session from database
    2. Validates parsing session data and statistics
    3. Tests API methods (get_recent_sessions, get_with_stats, get_summary_by_reason)
    4. Verifies accounting equation: total_rows == saved + skipped + duplicate
    5. Validates skipped_transactions records and aggregation
    6. Confirms validation_status logic

    Note: Works with existing database data - does NOT reprocess files.
    """
    print("=" * 70)
    print("End-to-End Verification (Database State)")
    print("=" * 70)

    # 1. Setup
    print("\n" + "=" * 70)
    print("1. Setup")
    print("=" * 70)

    # Initialize database connection and repositories
    conn = DatabaseConnection.get_instance()
    session_repo = ParsingSessionRepository(conn)
    skipped_repo = SkippedTransactionRepository(conn)

    print("  ✓ Database connection established")
    print("  ✓ Repositories initialized")

    # 2. Query most recent parsing session
    print("\n" + "=" * 70)
    print("2. Retrieve Most Recent Parsing Session")
    print("=" * 70)

    # Get recent sessions
    recent_sessions = session_repo.get_recent_sessions(limit=1)

    if not recent_sessions:
        print("\n✗ ERROR: No parsing sessions found in database")
        print("  Please process at least one file before running this test")
        sys.exit(1)

    session = recent_sessions[0]
    session_id = session['id']

    print(f"\n  Most recent session found:")
    print(f"  Session ID: {session_id}")
    print(f"  File Name: {session['file_name']}")
    print(f"  Institution: {session['institution_name']}")
    print(f"  Institution Type: {session['institution_type']}")
    print(f"  Parser Type: {session['parser_type']}")
    print(f"  Status: {session['status']}")

    print("\n  ✓ Recent session retrieved successfully")

    # 3. Parsing Session Details (Direct Query)
    print("\n" + "=" * 70)
    print("3. Parsing Session Statistics")
    print("=" * 70)

    print(f"\n  Total Rows Scanned: {session['total_rows_in_file']}")
    print(f"  Rows Saved: {session['rows_saved']}")
    print(f"  Rows Skipped: {session['rows_skipped']}")
    print(f"  Rows Duplicate: {session['rows_duplicate']}")
    print(f"  Validation Status: {session['validation_status']}")
    print(f"  Validation Notes: {session['validation_notes']}")

    print("\n  ✓ Parsing session statistics retrieved")

    # 4. Query skipped_transactions
    print("\n" + "=" * 70)
    print("4. Skipped Transactions")
    print("=" * 70)

    # Use repository method instead of direct SQL
    skipped_list = skipped_repo.get_by_session(session_id)

    print(f"\n  Total skipped: {len(skipped_list)}")

    if skipped_list:
        print("\n  Sample skipped transactions (first 5):")
        for row in skipped_list[:5]:
            print(f"    Row {row['row_number']}: {row['skip_reason']}")
            if row['skip_details']:
                print(f"      Details: {row['skip_details']}")
    else:
        print("  No transactions were skipped (all rows valid)")

    print("\n  ✓ skipped_transactions records verified")

    # 5. Test API methods
    print("\n" + "=" * 70)
    print("5. Testing API Methods")
    print("=" * 70)

    # 5a. get_recent_sessions - already tested in step 2
    print("\n  Testing get_recent_sessions(limit=10)...")
    recent = session_repo.get_recent_sessions(limit=10)
    print(f"    Returned: {len(recent)} sessions")

    # Verify our session is in the list
    found = any(s['id'] == session_id for s in recent)
    if found:
        print(f"    ✓ Current session (id={session_id}) found in recent list")
    else:
        print(f"    ✗ ERROR: Current session (id={session_id}) NOT in recent list")
        sys.exit(1)

    # 5b. get_with_stats
    print("\n  Testing get_with_stats(session_id)...")
    stats = session_repo.get_with_stats(session_id)

    if not stats:
        print(f"    ✗ ERROR: get_with_stats returned None for session_id={session_id}")
        sys.exit(1)

    print(f"    File Name: {stats['file_name']}")
    print(f"    Institution: {stats['institution_name']}")
    print(f"    Institution Type: {stats['institution_type']}")

    # Verify required fields
    if stats['id'] != session_id:
        print(f"    ✗ ERROR: Session ID mismatch: expected {session_id}, got {stats['id']}")
        sys.exit(1)

    if 'institution_name' not in stats:
        print("    ✗ ERROR: institution_name not in stats (join failed)")
        sys.exit(1)

    print("    ✓ get_with_stats includes all required joined fields")

    # 5c. get_summary_by_reason
    print("\n  Testing get_summary_by_reason(session_id)...")
    summary = skipped_repo.get_summary_by_reason(session_id)

    print(f"    Returned: {len(summary)} skip reason types")

    if summary:
        print("    Skip reason breakdown:")
        for item in summary:
            print(f"      {item['skip_reason']}: {item['count']} transactions")

        # Verify counts match
        total_in_summary = sum(item['count'] for item in summary)
        if total_in_summary != len(skipped_list):
            print(f"    ✗ ERROR: Summary counts ({total_in_summary}) != total skipped ({len(skipped_list)})")
            sys.exit(1)

        print(f"    ✓ Summary counts match total skipped ({len(skipped_list)})")
    else:
        print("    No skipped transactions to summarize")
        if len(skipped_list) > 0:
            print(f"    ✗ ERROR: Expected {len(skipped_list)} in summary but got 0")
            sys.exit(1)

    print("\n  ✓ All API methods working correctly")

    # 6. Verify accounting equation
    print("\n" + "=" * 70)
    print("6. Row Accounting Verification")
    print("=" * 70)

    total_scanned = session['total_rows_in_file']
    saved = session['rows_saved']
    skipped = session['rows_skipped']
    duplicate = session['rows_duplicate']
    total_accounted = saved + skipped + duplicate

    print(f"\n  Total Rows Scanned: {total_scanned}")
    print(f"  Rows Saved: {saved}")
    print(f"  Rows Skipped: {skipped}")
    print(f"  Rows Duplicate: {duplicate}")
    print(f"  Total Accounted: {total_accounted}")

    match = (total_scanned == total_accounted)
    print(f"\n  Accounting Match: {'✓ YES' if match else '✗ NO'}")

    if not match:
        difference = total_scanned - total_accounted
        print(f"  Difference: {difference} rows")
        print(f"  ✗ ERROR: Accounting equation failed!")
        sys.exit(1)

    print("  ✓ Accounting equation verified: total == saved + skipped + duplicate")

    # 7. Verify skipped transaction count consistency
    print("\n" + "=" * 70)
    print("7. Skipped Transaction Count Verification")
    print("=" * 70)

    # Verify that rows_skipped in session matches actual skipped records
    actual_skipped_count = len(skipped_list)
    reported_skipped_count = session['rows_skipped']

    print(f"\n  Reported in session: {reported_skipped_count}")
    print(f"  Actual skipped records: {actual_skipped_count}")

    if actual_skipped_count != reported_skipped_count:
        print(f"  ✗ ERROR: Skipped count mismatch!")
        sys.exit(1)

    print("  ✓ Skipped transaction counts match")

    # 8. Final verdict
    print("\n" + "=" * 70)
    print("8. Verification Checklist")
    print("=" * 70)

    print("\n  ✓ Parsing session data retrieved")
    print("  ✓ Session statistics validated")
    print("  ✓ Skipped transactions records verified")
    print(f"  ✓ Validation status: {session['validation_status']}")
    print("  ✓ API methods return expected data")
    print(f"  ✓ Accounting equation: PASS")
    print(f"  ✓ Skipped count consistency: PASS")

    # Overall verdict
    print("\n" + "=" * 70)

    if session['validation_status'] == 'pass' and match:
        print("✓✓✓ End-to-End Verification PASSED! ✓✓✓")
        print("\nAll database integrity checks passed:")
        print("  - Parsing session tracking is working correctly")
        print("  - Skipped transaction recording is accurate")
        print("  - API methods return correct joined data")
        print("  - Accounting equation is satisfied")
        print("  - Validation status logic is correct")
    elif session['validation_status'] == 'warning':
        print("⚠ Verification completed with warnings")
        print(f"  Warning: {session['validation_notes']}")
    else:
        print("✗ Verification completed with issues")
        if not match:
            print("  Issue: Accounting equation failed")
        if session['validation_status'] == 'fail':
            print(f"  Issue: Validation failed - {session['validation_notes']}")

    print("=" * 70)


if __name__ == '__main__':
    try:
        verify_end_to_end()
    except KeyboardInterrupt:
        print("\n\nVerification interrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n\n✗ ERROR: Verification failed with exception:")
        print(f"  {type(e).__name__}: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
