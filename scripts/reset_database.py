#!/usr/bin/env python3
"""
Database Reset Script for Expense Tracker

Safely resets transaction data while preserving master data (categories, institutions, users).
Creates automatic backups and includes dry-run mode for safety.

Usage:
    python scripts/reset_database.py --dry-run  # Preview only
    python scripts/reset_database.py             # Execute with confirmation
    python scripts/reset_database.py --force     # Execute without confirmation

Safety Features:
    - Automatic timestamped backup before any changes
    - Transaction-based execution (automatic rollback on error)
    - Dry-run mode for preview
    - User confirmation prompt (skippable with --force)
    - Validation queries after execution
    - Foreign key constraint handling

Master Data Preservation:
    - categories table (23 records)
    - financial_institutions table (7 records)
    - users table (1 record)
    - category_merchant_mappings table (merchant-category mappings for auto-categorization)
    - _migrations table (migration history)

Tables to Reset:
    - transactions (all records deleted)
    - duplicate_transaction_confirmations (cascade delete)
    - skipped_transactions (cascade delete)
    - parsing_sessions (cascade delete)
    - processed_files (all records deleted)

Author: Senior Backend Architect
Date: 2026-01-12
"""

import sys
import os
import argparse
import logging
import shutil
import sqlite3
from datetime import datetime
from typing import Dict, Any

# Add project root to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from src.config import DIRECTORIES

# Configuration
DB_PATH = os.path.join(DIRECTORIES['data'], 'expense_tracker.db')
BACKUP_DIR = os.path.join(DIRECTORIES['data'], 'backups')

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


def create_backup(db_path: str) -> str:
    """
    Create timestamped backup of database.

    Args:
        db_path: Path to database file

    Returns:
        str: Path to backup file

    Raises:
        Exception: If backup creation fails
    """
    # Create backups directory if it doesn't exist
    os.makedirs(BACKUP_DIR, exist_ok=True)

    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    backup_filename = f'expense_tracker_{timestamp}.db'
    backup_path = os.path.join(BACKUP_DIR, backup_filename)

    try:
        shutil.copy2(db_path, backup_path)
        logger.info(f'Backup created: {backup_path}')
        return backup_path
    except Exception as e:
        logger.error(f'Failed to create backup: {e}')
        raise


def get_table_counts(conn: sqlite3.Connection) -> Dict[str, int]:
    """
    Get record counts for all relevant tables.

    Args:
        conn: Database connection

    Returns:
        Dict mapping table names to record counts
    """
    tables = [
        'transactions',
        'duplicate_transaction_confirmations',
        'skipped_transactions',
        'parsing_sessions',
        'processed_files',
        'categories',
        'financial_institutions',
        'users',
        'category_merchant_mappings'
    ]

    counts = {}
    for table in tables:
        try:
            cursor = conn.execute(f'SELECT COUNT(*) FROM {table}')
            counts[table] = cursor.fetchone()[0]
        except sqlite3.OperationalError:
            counts[table] = 0  # Table doesn't exist

    return counts


def print_status(title: str, counts: Dict[str, int]):
    """
    Print formatted table status.

    Args:
        title: Section title
        counts: Dictionary of table counts
    """
    print(f'\n{"="*80}')
    print(f'{title}')
    print(f'{"="*80}')

    print(f'\nTables to Reset:')
    print(f'  transactions: {counts.get("transactions", 0):,} records')
    print(f'  duplicate_transaction_confirmations: {counts.get("duplicate_transaction_confirmations", 0):,} records')
    print(f'  skipped_transactions: {counts.get("skipped_transactions", 0):,} records')
    print(f'  parsing_sessions: {counts.get("parsing_sessions", 0):,} records')
    print(f'  processed_files: {counts.get("processed_files", 0):,} records')

    print(f'\nMaster Data (Preserved):')
    print(f'  categories: {counts.get("categories", 0):,} records')
    print(f'  financial_institutions: {counts.get("financial_institutions", 0):,} records')
    print(f'  users: {counts.get("users", 0):,} records')
    print(f'  category_merchant_mappings: {counts.get("category_merchant_mappings", 0):,} records')

    total_to_delete = sum([
        counts.get("transactions", 0),
        counts.get("duplicate_transaction_confirmations", 0),
        counts.get("skipped_transactions", 0),
        counts.get("parsing_sessions", 0),
        counts.get("processed_files", 0)
    ])
    print(f'\nTotal Records to Delete: {total_to_delete:,}')
    print('='*80 + '\n')


def reset_database(conn: sqlite3.Connection, dry_run: bool = False) -> Dict[str, Any]:
    """
    Reset database by deleting transaction data while preserving master data.

    Master data preserved:
    - categories (expense categories)
    - financial_institutions (bank/card providers)
    - users (system users)
    - category_merchant_mappings (auto-categorization training data)
    - _migrations (schema version history)

    Deletion order respects foreign key constraints:
    1. duplicate_transaction_confirmations (references transactions, parsing_sessions)
    2. skipped_transactions (references parsing_sessions)
    3. parsing_sessions (references processed_files)
    4. transactions (references processed_files)
    5. processed_files (references financial_institutions)

    Args:
        conn: Database connection
        dry_run: If True, only preview without executing

    Returns:
        Dict with deletion statistics
    """
    logger.info(f'Starting database reset (dry_run={dry_run})...')

    # Get counts before deletion
    before_counts = get_table_counts(conn)

    if dry_run:
        logger.info('DRY-RUN MODE: No changes will be made')
        return {'before': before_counts, 'after': before_counts, 'deleted': {}}

    try:
        # Start transaction
        conn.execute('BEGIN TRANSACTION')
        logger.debug('Transaction started')

        # Enable foreign keys
        conn.execute('PRAGMA foreign_keys=ON')
        logger.debug('Foreign key constraints enabled')

        # Delete in correct order to respect foreign key constraints
        # NOTE: category_merchant_mappings is preserved as master data
        deletion_order = [
            'duplicate_transaction_confirmations',
            'skipped_transactions',
            'parsing_sessions',
            'transactions',
            'processed_files'
        ]

        deleted_counts = {}
        for table in deletion_order:
            cursor = conn.execute(f'DELETE FROM {table}')
            deleted_counts[table] = cursor.rowcount
            logger.info(f'Deleted {deleted_counts[table]:,} records from {table}')

        # Reset AUTOINCREMENT sequences for fresh start
        logger.info('Resetting AUTOINCREMENT sequences...')
        for table in deletion_order:
            conn.execute(f"DELETE FROM sqlite_sequence WHERE name='{table}'")
            logger.debug(f'Reset sequence for {table}')

        # Commit transaction
        conn.commit()
        logger.info('Transaction committed successfully')

        # Get counts after deletion
        after_counts = get_table_counts(conn)

        # Verify master data preservation
        if after_counts['categories'] == before_counts['categories'] and \
           after_counts['financial_institutions'] == before_counts['financial_institutions'] and \
           after_counts['users'] == before_counts['users'] and \
           after_counts['category_merchant_mappings'] == before_counts['category_merchant_mappings']:
            logger.info('✓ Master data preservation verified')
        else:
            logger.error('✗ Master data was modified!')
            raise Exception('Master data was unexpectedly modified')

        # Verify transaction data deletion
        if after_counts['transactions'] == 0 and \
           after_counts['processed_files'] == 0:
            logger.info('✓ Transaction data deletion verified')
        else:
            logger.error('✗ Transaction data was not fully deleted!')
            raise Exception('Transaction data deletion incomplete')

        return {
            'before': before_counts,
            'after': after_counts,
            'deleted': deleted_counts
        }

    except Exception as e:
        # Rollback on error
        conn.rollback()
        logger.error(f'Transaction rolled back due to error: {e}')
        raise


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description='Reset database transaction data while preserving master data',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
Examples:
  # Preview changes without executing
  python scripts/reset_database.py --dry-run

  # Execute with confirmation prompt
  python scripts/reset_database.py

  # Execute without confirmation (use with caution)
  python scripts/reset_database.py --force

Safety Features:
  - Automatic timestamped backup before any changes
  - Transaction-based execution (auto-rollback on error)
  - Master data preservation (categories, institutions, users, merchant mappings)
  - Validation queries after execution
        '''
    )
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Preview only, do not execute changes'
    )
    parser.add_argument(
        '--force',
        action='store_true',
        help='Skip confirmation prompt'
    )

    args = parser.parse_args()

    # Check database exists
    if not os.path.exists(DB_PATH):
        logger.error(f'Database not found: {DB_PATH}')
        return 1

    # Connect to database
    logger.info(f'Connecting to database: {DB_PATH}')
    conn = sqlite3.connect(DB_PATH, timeout=30.0)

    try:
        # Get initial counts
        initial_counts = get_table_counts(conn)
        print_status('CURRENT DATABASE STATE', initial_counts)

        # Dry-run mode
        if args.dry_run:
            logger.info('DRY-RUN MODE: Preview only')
            print('This is a preview. No changes will be made.')
            print('Run without --dry-run to execute the reset.')
            return 0

        # Confirmation prompt
        if not args.force:
            total_to_delete = sum([
                initial_counts.get("transactions", 0),
                initial_counts.get("duplicate_transaction_confirmations", 0),
                initial_counts.get("skipped_transactions", 0),
                initial_counts.get("parsing_sessions", 0),
                initial_counts.get("processed_files", 0)
            ])

            print(f'\n⚠️  WARNING: This will DELETE {total_to_delete:,} records!')
            print('Master data (categories, institutions, users, merchant mappings) will be preserved.')
            print('\nA backup will be created automatically before proceeding.')

            response = input('\nType "yes" to continue: ')
            if response.lower() != 'yes':
                print('Operation cancelled.')
                return 0

        # Create backup before any changes
        logger.info('Creating backup before reset...')
        backup_path = create_backup(DB_PATH)
        print(f'\n✓ Backup created: {backup_path}')

        # Execute reset
        logger.info('Executing database reset...')
        result = reset_database(conn, dry_run=False)

        # Print results
        print_status('DATABASE STATE AFTER RESET', result['after'])

        print('\n' + '='*80)
        print('RESET COMPLETE')
        print('='*80)
        print(f'\nDeleted Records:')
        for table, count in result['deleted'].items():
            print(f'  {table}: {count:,} records')

        print(f'\nBackup Location: {backup_path}')
        print('\nMaster data preserved:')
        print(f'  categories: {result["after"]["categories"]} records')
        print(f'  financial_institutions: {result["after"]["financial_institutions"]} records')
        print(f'  users: {result["after"]["users"]} records')
        print(f'  category_merchant_mappings: {result["after"]["category_merchant_mappings"]} records')

        print('\n✓ Database reset completed successfully!')
        print('='*80 + '\n')

        logger.info('Database reset completed successfully')
        return 0

    except Exception as e:
        logger.error(f'Database reset failed: {e}', exc_info=True)
        print(f'\n✗ Error: {e}')
        print('\nThe database has been rolled back to its previous state.')
        print('If you created a backup, you can restore it manually.')
        return 1

    finally:
        conn.close()
        logger.debug('Database connection closed')


if __name__ == '__main__':
    sys.exit(main())
