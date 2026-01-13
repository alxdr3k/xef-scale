#!/usr/bin/env python3
"""
Merchant Mapping Regeneration Script for Expense Tracker

Regenerates category-merchant mappings from existing transaction data.
This script extracts unique merchant-category pairs from the transactions table
and populates the category_merchant_mappings table for auto-categorization.

Usage:
    python scripts/regenerate_merchant_mappings.py                # Execute with confirmation
    python scripts/regenerate_merchant_mappings.py --dry-run      # Preview only
    python scripts/regenerate_merchant_mappings.py --force        # Execute without confirmation
    python scripts/regenerate_merchant_mappings.py --verbose      # Show detailed output

Features:
    - Idempotent: Safe to run multiple times (skips duplicates)
    - Transaction-based: Automatic rollback on error
    - Validates data integrity before commit
    - Shows before/after statistics
    - Handles foreign key constraints properly

Expected Outcome:
    - 715+ merchant mappings regenerated from historical transaction data
    - Mappings exclude '기타' (other/misc) category for better classification

Author: Database Architect
Date: 2026-01-14
Task: Restore merchant mapping data lost during database reset
"""

import sys
import os
import argparse
import logging
import sqlite3
from datetime import datetime
from typing import Dict, Tuple

# Add project root to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from src.config import DIRECTORIES

# Configuration
DB_PATH = os.path.join(DIRECTORIES['data'], 'expense_tracker.db')

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


def get_current_stats(conn: sqlite3.Connection) -> Dict[str, int]:
    """
    Get current statistics about mappings and transactions.

    Args:
        conn: Database connection

    Returns:
        Dict with counts for mappings, transactions, and categories
    """
    stats = {}

    # Count existing mappings
    cursor = conn.execute('SELECT COUNT(*) FROM category_merchant_mappings')
    stats['existing_mappings'] = cursor.fetchone()[0]

    # Count total transactions
    cursor = conn.execute('SELECT COUNT(*) FROM transactions')
    stats['total_transactions'] = cursor.fetchone()[0]

    # Count transactions with merchant names
    cursor = conn.execute('''
        SELECT COUNT(*) FROM transactions
        WHERE merchant_name IS NOT NULL AND merchant_name <> ''
    ''')
    stats['transactions_with_merchants'] = cursor.fetchone()[0]

    # Count unique merchant-category pairs (potential new mappings)
    cursor = conn.execute('''
        SELECT COUNT(DISTINCT t.merchant_name || '|' || t.category_id)
        FROM transactions t
        WHERE t.merchant_name IS NOT NULL
          AND t.merchant_name <> ''
          AND t.category_id IS NOT NULL
          AND t.category_id <> (SELECT id FROM categories WHERE name = '기타' LIMIT 1)
    ''')
    stats['potential_mappings'] = cursor.fetchone()[0]

    # Count categories
    cursor = conn.execute('SELECT COUNT(*) FROM categories')
    stats['total_categories'] = cursor.fetchone()[0]

    return stats


def regenerate_mappings(conn: sqlite3.Connection, dry_run: bool = False, verbose: bool = False) -> Tuple[int, int]:
    """
    Regenerate merchant mappings from transaction data.

    Logic mirrors migration 007_add_category_merchant_mappings.sql:
    - Extract distinct merchant-category pairs from transactions
    - Exclude '기타' category for better classification quality
    - Use 'exact' match type with 100 confidence
    - Mark source as 'imported_2024_2025' for audit trail
    - Skip duplicates (ON CONFLICT DO NOTHING)

    Args:
        conn: Database connection
        dry_run: If True, only preview without executing
        verbose: If True, show detailed per-category statistics

    Returns:
        Tuple of (new_mappings_count, total_mappings_count)

    Raises:
        Exception: If regeneration fails
    """
    logger.info(f'Starting merchant mapping regeneration (dry_run={dry_run})...')

    # Get stats before regeneration
    before_stats = get_current_stats(conn)
    logger.info(f'Before: {before_stats["existing_mappings"]} existing mappings')

    if dry_run:
        # Show what would be inserted without executing
        cursor = conn.execute('''
            SELECT
                c.name as category_name,
                COUNT(DISTINCT t.merchant_name) as unique_merchants
            FROM transactions t
            JOIN categories c ON t.category_id = c.id
            WHERE t.merchant_name IS NOT NULL
              AND t.merchant_name <> ''
              AND t.category_id <> (SELECT id FROM categories WHERE name = '기타' LIMIT 1)
              AND NOT EXISTS (
                  SELECT 1 FROM category_merchant_mappings cmm
                  WHERE cmm.category_id = t.category_id
                    AND cmm.merchant_pattern = t.merchant_name
                    AND cmm.match_type = 'exact'
              )
            GROUP BY c.name
            ORDER BY unique_merchants DESC
        ''')

        preview_data = cursor.fetchall()
        if preview_data:
            print('\nMappings to be created:')
            print(f'{"Category":<30} {"New Mappings":>15}')
            print('-' * 50)
            total_preview = 0
            for category, count in preview_data:
                print(f'{category:<30} {count:>15,}')
                total_preview += count
            print('-' * 50)
            print(f'{"TOTAL":<30} {total_preview:>15,}')
        else:
            print('\nNo new mappings to create (all mappings already exist)')

        return 0, before_stats['existing_mappings']

    try:
        # Start transaction
        conn.execute('BEGIN TRANSACTION')
        logger.debug('Transaction started')

        # Enable foreign keys
        conn.execute('PRAGMA foreign_keys=ON')
        logger.debug('Foreign key constraints enabled')

        # Regenerate mappings using logic from migration 007
        # This query mirrors the INSERT statement from lines 84-96 of the migration
        cursor = conn.execute('''
            INSERT INTO category_merchant_mappings (category_id, merchant_pattern, match_type, confidence, source)
            SELECT
                t.category_id,
                t.merchant_name as merchant_pattern,
                'exact' as match_type,
                100 as confidence,
                'imported_2024_2025' as source
            FROM transactions t
            WHERE t.merchant_name IS NOT NULL
              AND t.merchant_name <> ''
              AND t.category_id IS NOT NULL
              AND t.category_id <> (SELECT id FROM categories WHERE name = '기타' LIMIT 1)
            GROUP BY t.category_id, t.merchant_name
            HAVING COUNT(*) >= 1
            ON CONFLICT (category_id, merchant_pattern, match_type) DO NOTHING
        ''')

        new_mappings = cursor.rowcount
        logger.info(f'Inserted {new_mappings} new merchant mappings')

        # Get stats after regeneration
        after_stats = get_current_stats(conn)
        total_mappings = after_stats['existing_mappings']

        # Validate results
        if total_mappings < before_stats['existing_mappings']:
            raise Exception('Mapping count decreased - data integrity violation')

        if new_mappings > 0:
            logger.info(f'✓ Successfully added {new_mappings} new mappings')
        else:
            logger.info('✓ No new mappings needed (all existing mappings already present)')

        # Show per-category statistics if verbose
        if verbose:
            cursor = conn.execute('''
                SELECT
                    c.name as category_name,
                    COUNT(*) as mapping_count
                FROM category_merchant_mappings cm
                JOIN categories c ON cm.category_id = c.id
                GROUP BY c.name
                ORDER BY mapping_count DESC
            ''')

            print('\nMapping distribution by category:')
            print(f'{"Category":<30} {"Mappings":>15}')
            print('-' * 50)
            for category, count in cursor.fetchall():
                print(f'{category:<30} {count:>15,}')

        # Commit transaction
        conn.commit()
        logger.info('Transaction committed successfully')

        return new_mappings, total_mappings

    except Exception as e:
        # Rollback on error
        conn.rollback()
        logger.error(f'Transaction rolled back due to error: {e}')
        raise


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description='Regenerate merchant-category mappings from transaction data',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
Examples:
  # Preview what mappings would be created
  python scripts/regenerate_merchant_mappings.py --dry-run

  # Execute with confirmation prompt
  python scripts/regenerate_merchant_mappings.py

  # Execute without confirmation
  python scripts/regenerate_merchant_mappings.py --force

  # Show detailed per-category statistics
  python scripts/regenerate_merchant_mappings.py --verbose

Features:
  - Idempotent: Safe to run multiple times
  - Transaction-based: Automatic rollback on error
  - Skips duplicates automatically
  - Validates data integrity before commit

Expected Outcome:
  - 715+ merchant mappings from historical transaction data
  - Mappings exclude '기타' category for better classification
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
    parser.add_argument(
        '--verbose',
        action='store_true',
        help='Show detailed per-category statistics'
    )

    args = parser.parse_args()

    # Set logging level
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    # Check database exists
    if not os.path.exists(DB_PATH):
        logger.error(f'Database not found: {DB_PATH}')
        return 1

    # Connect to database
    logger.info(f'Connecting to database: {DB_PATH}')
    conn = sqlite3.connect(DB_PATH, timeout=30.0)

    try:
        # Get initial stats
        initial_stats = get_current_stats(conn)

        print('\n' + '='*80)
        print('MERCHANT MAPPING REGENERATION')
        print('='*80)
        print(f'\nCurrent State:')
        print(f'  Existing mappings: {initial_stats["existing_mappings"]:,}')
        print(f'  Total transactions: {initial_stats["total_transactions"]:,}')
        print(f'  Transactions with merchants: {initial_stats["transactions_with_merchants"]:,}')
        print(f'  Potential new mappings: {initial_stats["potential_mappings"]:,}')
        print(f'  Total categories: {initial_stats["total_categories"]:,}')
        print('='*80)

        # Dry-run mode
        if args.dry_run:
            logger.info('DRY-RUN MODE: Preview only')
            print('\nPREVIEW MODE: No changes will be made')
            regenerate_mappings(conn, dry_run=True, verbose=args.verbose)
            print('\nRun without --dry-run to execute the regeneration.')
            return 0

        # Confirmation prompt
        if not args.force and initial_stats['potential_mappings'] > 0:
            print(f'\nThis will create up to {initial_stats["potential_mappings"]:,} new merchant mappings.')
            print('The operation is idempotent and will skip any existing mappings.')

            response = input('\nType "yes" to continue: ')
            if response.lower() != 'yes':
                print('Operation cancelled.')
                return 0

        # Execute regeneration
        logger.info('Executing merchant mapping regeneration...')
        new_count, total_count = regenerate_mappings(conn, dry_run=False, verbose=args.verbose)

        # Print results
        print('\n' + '='*80)
        print('REGENERATION COMPLETE')
        print('='*80)
        print(f'\nResults:')
        print(f'  New mappings created: {new_count:,}')
        print(f'  Total mappings: {total_count:,}')
        print(f'  Source transactions: {initial_stats["transactions_with_merchants"]:,}')

        if new_count > 0:
            print(f'\n✓ Successfully regenerated {new_count} merchant mappings from {initial_stats["transactions_with_merchants"]} transactions')
        else:
            print(f'\n✓ All mappings already exist - no regeneration needed')

        print('='*80 + '\n')

        logger.info('Merchant mapping regeneration completed successfully')
        return 0

    except Exception as e:
        logger.error(f'Merchant mapping regeneration failed: {e}', exc_info=True)
        print(f'\n✗ Error: {e}')
        print('\nThe database has been rolled back to its previous state.')
        return 1

    finally:
        conn.close()
        logger.debug('Database connection closed')


if __name__ == '__main__':
    sys.exit(main())
