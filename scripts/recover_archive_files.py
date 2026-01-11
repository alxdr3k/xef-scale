#!/usr/bin/env python3
"""
Archive File Recovery Script for Hana Card Excel Files

Recovers transactions from archived Hana Card Excel files that were not
previously imported to the database. Scans both main archive folder and
duplicates subfolder.

Usage:
    python scripts/recover_archive_files.py --dry-run  # Preview only
    python scripts/recover_archive_files.py             # Actually recover

Features:
    - Automatic database backup before recovery
    - Duplicate detection (INSERT OR IGNORE)
    - Detailed recovery statistics
    - Sample transaction verification
"""

import sys
import os
import glob
import logging
import argparse
import shutil
from typing import List, Dict, Tuple
from datetime import datetime

# Add project root to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from src.db.connection import DatabaseConnection
from src.db.repository import (
    CategoryRepository,
    InstitutionRepository,
    TransactionRepository
)
from src.parsers.hana_parser import HanaCardParser
from src.models import Transaction, ParseResult

# Configuration
ARCHIVE_DIR = 'archive'
DUPLICATES_DIR = 'archive/duplicates'
INSTITUTION_NAME = '하나카드'

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


def backup_db() -> str:
    """
    Create timestamped backup of database before recovery.

    Returns:
        str: Path to backup file

    Raises:
        Exception: If backup creation fails
    """
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    src = 'data/expense_tracker.db'
    dst = f'data/expense_tracker.db.backup.{timestamp}'

    try:
        shutil.copy2(src, dst)
        logger.info(f'Backup created: {dst}')
        return dst
    except Exception as e:
        logger.error(f'Failed to create backup: {e}')
        raise


def find_archive_files(project_root: str) -> List[str]:
    """
    Find all .xls files in archive folders.

    Searches both main archive folder and duplicates subfolder.

    Args:
        project_root: Project root directory path

    Returns:
        List of absolute file paths to .xls files
    """
    files = []

    # Search main archive folder
    archive_path = os.path.join(project_root, ARCHIVE_DIR, '*.xls')
    files.extend(glob.glob(archive_path))

    # Search duplicates subfolder
    duplicates_path = os.path.join(project_root, DUPLICATES_DIR, '*.xls')
    files.extend(glob.glob(duplicates_path))

    logger.info(f'Found {len(files)} .xls files in archive folders')
    return files


def parse_archive_file(file_path: str, parser: HanaCardParser) -> Tuple[ParseResult, str]:
    """
    Parse a single archive file using HanaCardParser.

    Args:
        file_path: Path to .xls file
        parser: HanaCardParser instance

    Returns:
        Tuple of (ParseResult, file_basename)
    """
    basename = os.path.basename(file_path)
    logger.info(f'Parsing: {basename}')

    try:
        result = parser.parse(file_path)
        logger.info(
            f'  Parsed {len(result.transactions)} transactions, '
            f'skipped {len(result.skipped)}'
        )
        return result, basename
    except Exception as e:
        logger.error(f'  Failed to parse {basename}: {e}')
        raise


def get_db_stats(conn) -> Dict[str, int]:
    """
    Get current database statistics.

    Args:
        conn: Database connection

    Returns:
        Dict with 'total' and 'hana' transaction counts
    """
    cursor = conn.execute(
        "SELECT COUNT(*) FROM transactions WHERE deleted_at IS NULL"
    )
    total = cursor.fetchone()[0]

    cursor = conn.execute("""
        SELECT COUNT(*) FROM transactions
        WHERE institution_id = (
            SELECT id FROM financial_institutions WHERE name='하나카드'
        )
        AND deleted_at IS NULL
    """)
    hana_count = cursor.fetchone()[0]

    return {'total': total, 'hana': hana_count}


def print_sample_transactions(conn, limit: int = 5):
    """
    Print sample transactions from Hana Card.

    Args:
        conn: Database connection
        limit: Number of sample transactions to show
    """
    cursor = conn.execute("""
        SELECT
            t.transaction_date,
            c.name as category,
            t.merchant_name,
            t.amount
        FROM transactions t
        JOIN categories c ON t.category_id = c.id
        JOIN financial_institutions fi ON t.institution_id = fi.id
        WHERE fi.name = '하나카드'
        AND t.deleted_at IS NULL
        ORDER BY t.transaction_date DESC
        LIMIT ?
    """, (limit,))

    print(f"\n{'Date':<12} {'Category':<15} {'Merchant':<35} {'Amount':>12}")
    print('-' * 80)
    for row in cursor.fetchall():
        print(
            f"{row['transaction_date']:<12} "
            f"{row['category']:<15} "
            f"{row['merchant_name'][:33]:<35} "
            f"{row['amount']:>12,}원"
        )


def print_dry_run_summary(
    files: List[str],
    all_transactions: List[Transaction],
    file_stats: Dict[str, Tuple[int, int]]
):
    """
    Print summary for dry-run mode.

    Args:
        files: List of archive file paths
        all_transactions: All parsed transactions
        file_stats: Dict mapping filename to (parsed_count, skipped_count)
    """
    print('\n' + '='*80)
    print('DRY-RUN PREVIEW - No data will be inserted to database')
    print('='*80)

    print(f'\nFiles Found: {len(files)}')
    for file_path in files:
        basename = os.path.basename(file_path)
        if basename in file_stats:
            parsed, skipped = file_stats[basename]
            print(f'  {basename}')
            print(f'    Parsed: {parsed}, Skipped: {skipped}')

    print(f'\nTotal Transactions Ready for Import: {len(all_transactions)}')

    # Show sample transactions
    if all_transactions:
        print(f'\nSample Transactions (first 10):')
        print(f"{'Date':<12} {'Category':<15} {'Merchant':<35} {'Amount':>12}")
        print('-' * 80)
        for txn in all_transactions[:10]:
            print(
                f"{txn.date:<12} "
                f"{txn.category:<15} "
                f"{txn.item[:33]:<35} "
                f"{txn.amount:>12,}원"
            )

        if len(all_transactions) > 10:
            print(f'... and {len(all_transactions) - 10} more transactions')

    # Category breakdown
    category_counts = {}
    category_amounts = {}
    for txn in all_transactions:
        category_counts[txn.category] = category_counts.get(txn.category, 0) + 1
        category_amounts[txn.category] = category_amounts.get(txn.category, 0) + txn.amount

    print(f'\nCategory Breakdown:')
    print(f"{'Category':<20} {'Count':>8} {'Total Amount':>15}")
    print('-' * 50)
    for cat in sorted(category_counts.keys()):
        print(f"{cat:<20} {category_counts[cat]:>8} {category_amounts[cat]:>15,}원")

    print('\nTo actually import this data, run without --dry-run flag')
    print('='*80 + '\n')


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description='Recover transactions from archived Hana Card Excel files'
    )
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Preview only, do not insert to database'
    )
    parser.add_argument(
        '--verbose',
        action='store_true',
        help='Enable verbose logging'
    )

    args = parser.parse_args()

    # Set logging level
    if args.verbose:
        logger.setLevel(logging.DEBUG)
        logging.getLogger().setLevel(logging.DEBUG)

    # Get project root
    project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    # Find all archive files
    logger.info('Searching for archive files...')
    archive_files = find_archive_files(project_root)

    if not archive_files:
        logger.warning('No .xls files found in archive folders')
        return 0

    # Parse all files
    logger.info('Parsing archive files...')
    hana_parser = HanaCardParser()
    all_transactions = []
    file_stats = {}

    for file_path in archive_files:
        try:
            result, basename = parse_archive_file(file_path, hana_parser)
            all_transactions.extend(result.transactions)
            file_stats[basename] = (len(result.transactions), len(result.skipped))
        except Exception as e:
            logger.error(f'Skipping file due to error: {os.path.basename(file_path)}')
            continue

    logger.info(f'Total transactions parsed: {len(all_transactions)}')

    # Dry-run mode
    if args.dry_run:
        print_dry_run_summary(archive_files, all_transactions, file_stats)
        return 0

    # Create database backup before insertion
    logger.info('Creating database backup...')
    try:
        backup_path = backup_db()
        logger.info(f'Database backed up to: {backup_path}')
    except Exception as e:
        logger.error(f'Backup failed: {e}')
        return 1

    # Actually insert to database
    logger.info('Connecting to database...')
    conn = DatabaseConnection.get_instance()

    try:
        # Get stats before recovery
        stats_before = get_db_stats(conn)
        logger.info(
            f'Before recovery: {stats_before["total"]} total transactions, '
            f'{stats_before["hana"]} from 하나카드'
        )

        # Initialize repositories
        category_repo = CategoryRepository(conn)
        institution_repo = InstitutionRepository(conn)
        transaction_repo = TransactionRepository(conn, category_repo, institution_repo)

        # Ensure institution exists
        institution_id = institution_repo.get_or_create(INSTITUTION_NAME, 'CARD')
        logger.info(f'Using institution: {INSTITUTION_NAME} (id={institution_id})')

        # Batch insert
        logger.info(f'Inserting {len(all_transactions)} transactions...')
        inserted_count = transaction_repo.batch_insert(all_transactions)

        # Get stats after recovery
        stats_after = get_db_stats(conn)

        # Print summary
        print('\n' + '='*80)
        print('RECOVERY COMPLETE')
        print('='*80)

        print(f'\nFiles Processed: {len(archive_files)}')
        for basename, (parsed, skipped) in file_stats.items():
            print(f'  {basename}')
            print(f'    Parsed: {parsed}, Skipped: {skipped}')

        print(f'\nDatabase Statistics:')
        print(f'  Before: {stats_before["total"]} total, {stats_before["hana"]} from 하나카드')
        print(f'  After:  {stats_after["total"]} total, {stats_after["hana"]} from 하나카드')
        print(f'  Added:  {stats_after["total"] - stats_before["total"]} total, '
              f'{stats_after["hana"] - stats_before["hana"]} from 하나카드')

        print(f'\nTransaction Processing:')
        print(f'  Total parsed: {len(all_transactions)}')
        print(f'  Successfully inserted: {inserted_count}')
        print(f'  Duplicates skipped: {len(all_transactions) - inserted_count}')

        print(f'\nSample Hana Card Transactions (latest 5):')
        print_sample_transactions(conn, limit=5)

        print('\n' + '='*80 + '\n')

        logger.info('Recovery completed successfully')
        return 0

    except Exception as e:
        logger.error(f'Recovery failed: {e}', exc_info=True)
        return 1

    finally:
        DatabaseConnection.close()


if __name__ == '__main__':
    sys.exit(main())
