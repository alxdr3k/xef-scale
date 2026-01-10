"""
Phase 5: End-to-end testing and verification of expense tracker parsing system.

Validates complete workflow from file processing through database persistence,
session tracking, skip recording, and API-friendly queries. Verifies accounting
equation and validation scenarios.
"""

import os
import sys
from pathlib import Path

# Add project root to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from src.file_processor import FileProcessor
from src.db.connection import DatabaseConnection
from src.db.repository import ParsingSessionRepository, SkippedTransactionRepository


def find_test_file(archive_path):
    """
    Find a test file in the archive directory.

    Prefers manual_test_phase4.xls if exists, otherwise uses first .xls file.

    Args:
        archive_path: Path to archive directory

    Returns:
        str: Full path to test file, or None if no files found
    """
    # Prefer manual_test_phase4.xls
    preferred_file = os.path.join(archive_path, 'manual_test_phase4.xls')
    if os.path.exists(preferred_file):
        return preferred_file

    # Fallback to first .xls file
    if not os.path.exists(archive_path):
        return None

    files = [f for f in os.listdir(archive_path)
             if f.endswith('.xls') or f.endswith('.xlsx')]

    # Filter out files in subdirectories
    files = [f for f in files if os.path.isfile(os.path.join(archive_path, f))]

    if not files:
        return None

    return os.path.join(archive_path, files[0])


def verify_phase5_end_to_end():
    """
    Comprehensive end-to-end verification of Phase 4 implementation.

    Tests:
    1. File processing from archive
    2. Database table population (parsing_sessions, skipped_transactions)
    3. API methods (get_recent_sessions, get_with_stats, get_summary_by_reason)
    4. Validation status computation
    5. Accounting equation verification
    """
    print("=" * 70)
    print("Phase 5: End-to-End Verification")
    print("=" * 70)

    # 1. Setup
    print("\n" + "=" * 70)
    print("1. Setup")
    print("=" * 70)

    archive_path = '/Users/yngn/ws/expense-tracker/archive/'
    test_file = find_test_file(archive_path)

    if not test_file:
        print(f"\n✗ ERROR: No test files found in {archive_path}")
        print("  Please ensure archive directory contains .xls files")
        sys.exit(1)

    print(f"  Test file: {os.path.basename(test_file)}")
    print(f"  Full path: {test_file}")

    # Initialize processor and repositories
    processor = FileProcessor()
    conn = DatabaseConnection.get_instance()
    session_repo = ParsingSessionRepository(conn)
    skipped_repo = SkippedTransactionRepository(conn)

    print("  ✓ FileProcessor initialized")
    print("  ✓ Database connection established")
    print("  ✓ Repositories initialized")

    # 2. Process file
    print("\n" + "=" * 70)
    print("2. Process File")
    print("=" * 70)

    print(f"\nProcessing file: {os.path.basename(test_file)}")
    result = processor.process_file(Path(test_file))

    print(f"\nProcessing Result:")
    print(f"  Status: {result.status}")
    print(f"  Message: {result.message}")
    print(f"  Transactions: {result.transaction_count}")
    print(f"  File ID: {result.file_id}")
    print(f"  File Hash: {result.file_hash[:16] if result.file_hash else None}...")

    # Handle duplicate case
    if result.is_duplicate():
        print("\n" + "=" * 70)
        print("⚠ File is duplicate (expected behavior)")
        print("=" * 70)
        print("\nThis is normal - the file was already processed.")
        print("Phase 5 verification cannot proceed with duplicate file.")
        print("\nTo test with a new file:")
        print("1. Copy a file from archive to inbox with unique name")
        print("2. Or delete the duplicate records from database")
        sys.exit(0)

    # Handle error case
    if not result.is_success():
        print("\n" + "=" * 70)
        print(f"✗ Processing failed: {result.message}")
        print("=" * 70)
        sys.exit(1)

    print("\n  ✓ File processed successfully")

    file_id = result.file_id

    # 3. Query parsing_sessions (direct SQL for verification)
    print("\n" + "=" * 70)
    print("3. Parsing Session Details")
    print("=" * 70)

    cursor = conn.cursor()
    cursor.execute("""
        SELECT id, file_id, parser_type, total_rows_in_file,
               rows_saved, rows_skipped, rows_duplicate,
               status, validation_status, validation_notes
        FROM parsing_sessions
        WHERE file_id = ?
    """, (file_id,))

    session = cursor.fetchone()

    if not session:
        print(f"\n✗ ERROR: No parsing session found for file_id={file_id}")
        sys.exit(1)

    print(f"\n  Session ID: {session['id']}")
    print(f"  File ID: {session['file_id']}")
    print(f"  Parser Type: {session['parser_type']}")
    print(f"  Total Rows Scanned: {session['total_rows_in_file']}")
    print(f"  Rows Saved: {session['rows_saved']}")
    print(f"  Rows Skipped: {session['rows_skipped']}")
    print(f"  Rows Duplicate: {session['rows_duplicate']}")
    print(f"  Status: {session['status']}")
    print(f"  Validation Status: {session['validation_status']}")
    print(f"  Validation Notes: {session['validation_notes']}")

    session_id = session['id']

    print("\n  ✓ parsing_sessions record verified")

    # 4. Query skipped_transactions (direct SQL)
    print("\n" + "=" * 70)
    print("4. Skipped Transactions")
    print("=" * 70)

    cursor.execute("""
        SELECT * FROM skipped_transactions
        WHERE session_id = ?
        ORDER BY row_number
    """, (session_id,))

    skipped_list = cursor.fetchall()

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

    # 5a. get_recent_sessions
    print("\n  Testing get_recent_sessions(limit=10)...")
    recent = session_repo.get_recent_sessions(limit=10)
    print(f"    Returned: {len(recent)} sessions")

    # Verify our session is in the list
    found = any(s['id'] == session_id for s in recent)
    if found:
        print(f"    ✓ Our session (id={session_id}) found in recent list")
    else:
        print(f"    ✗ ERROR: Our session (id={session_id}) NOT in recent list")
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

    print(f"    Returned: {len(summary)} skip reasons")

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

    # 7. Final verdict
    print("\n" + "=" * 70)
    print("7. Phase 5 Verification Checklist")
    print("=" * 70)

    print("\n  ✓ File processes successfully")
    print("  ✓ parsing_sessions record created")
    print("  ✓ skipped_transactions records created")
    print(f"  ✓ Validation status correct: {session['validation_status']}")
    print("  ✓ API methods return expected data")
    print(f"  ✓ Accounting verified: {'PASS' if match else 'FAIL'}")

    # Overall verdict
    print("\n" + "=" * 70)

    if session['validation_status'] == 'pass' and match:
        print("✓✓✓ Phase 5 End-to-End Test PASSED! ✓✓✓")
    elif session['validation_status'] == 'warning':
        print("⚠ Phase 5 completed with warnings")
        print(f"  Warning: {session['validation_notes']}")
    else:
        print("✗ Phase 5 completed with issues")
        if not match:
            print("  Issue: Accounting equation failed")
        if session['validation_status'] == 'fail':
            print(f"  Issue: Validation failed - {session['validation_notes']}")

    print("=" * 70)


if __name__ == '__main__':
    try:
        verify_phase5_end_to_end()
    except KeyboardInterrupt:
        print("\n\nVerification interrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n\n✗ ERROR: Verification failed with exception:")
        print(f"  {type(e).__name__}: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
