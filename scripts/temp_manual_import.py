#!/usr/bin/env python3
"""
TEMPORARY ONE-TIME PARSER for manual transaction imports (2024.txt, 2025.txt)

This script is designed for one-time use and can be safely deleted after import.

Usage:
    python scripts/temp_manual_import.py --dry-run  # Preview only
    python scripts/temp_manual_import.py             # Actually import

Shrimp Task: 23fa5601-193a-4f53-9100-49e572da364d
"""

import sys
import os
import re
import logging
import argparse
from typing import List, Tuple, Dict
from datetime import datetime

# Add project root to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from src.db.connection import DatabaseConnection
from src.db.repository import (
    CategoryRepository,
    InstitutionRepository,
    TransactionRepository
)
from src.models import Transaction

# Configuration
FILE_2024 = '2024.txt'
FILE_2025 = '2025.txt'
INSTITUTION_NAME = '수동입력'

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


def parse_amount(amount_str: str) -> int:
    """
    Parse '₩29,000' → 29000

    Args:
        amount_str: Amount string with ₩ and commas (e.g., '₩29,000')

    Returns:
        int: Parsed amount

    Raises:
        ValueError: If amount cannot be parsed
    """
    # Remove ₩ symbol and commas
    cleaned = amount_str.replace('₩', '').replace(',', '').strip()
    return int(cleaned)


def parse_2024_file(file_path: str, verbose: bool = False) -> Tuple[List[Transaction], Dict[str, int]]:
    """
    Parse 2024.txt (no date column, only month)

    Format: 월<TAB>카테고리<TAB>내역<TAB>금액
    Example: 9월	구독	ChatGPT	₩29,000

    Args:
        file_path: Path to 2024.txt
        verbose: Enable verbose logging

    Returns:
        Tuple of (transactions: List[Transaction], stats: Dict[str, int])
    """
    transactions = []
    stats = {
        'total_lines': 0,
        'parsed': 0,
        'skipped_zero': 0,
        'skipped_empty_merchant': 0,
        'skipped_error': 0
    }

    logger.info(f'Parsing 2024.txt from: {file_path}')

    with open(file_path, 'r', encoding='utf-8') as f:
        for line_num, line in enumerate(f, start=1):
            stats['total_lines'] += 1
            line = line.strip()

            if not line:
                continue

            try:
                # Split by tab
                parts = line.split('\t')
                if len(parts) != 4:
                    logger.warning(f'Line {line_num}: Wrong number of fields ({len(parts)}), skipping: {line[:50]}...')
                    stats['skipped_error'] += 1
                    continue

                month_col, category, merchant, amount_str = parts

                # Extract month from "월" pattern (e.g., "9월" → month=9)
                match = re.search(r'(\d+)월', month_col)
                if not match:
                    logger.warning(f'Line {line_num}: Cannot extract month from: {month_col}')
                    stats['skipped_error'] += 1
                    continue

                month = int(match.group(1))

                # Parse amount
                amount = parse_amount(amount_str)

                # Skip zero amounts
                if amount == 0:
                    if verbose:
                        logger.debug(f'Line {line_num}: Skipping zero amount: {merchant}')
                    stats['skipped_zero'] += 1
                    continue

                # Skip empty merchant names
                if not merchant or merchant.strip() == '':
                    logger.warning(f'Line {line_num}: Empty merchant name, skipping')
                    stats['skipped_empty_merchant'] += 1
                    continue

                # Default empty category to "기타"
                if not category or category.strip() == '':
                    category = '기타'

                # Create date as 1st of each month (9월 → 2024-09-01)
                date_str = f'2024.{month:02d}.01'
                month_str = f'{month:02d}'

                # Create Transaction
                txn = Transaction(
                    month=month_str,
                    date=date_str,
                    category=category.strip(),
                    item=merchant.strip(),
                    amount=amount,
                    source=INSTITUTION_NAME,
                    installment_months=None,
                    installment_current=None,
                    original_amount=None,
                    file_id=None,
                    row_number_in_file=None
                )

                transactions.append(txn)
                stats['parsed'] += 1

                if verbose:
                    logger.debug(f'Line {line_num}: Parsed {date_str} {merchant.strip()} {amount}원')

            except Exception as e:
                logger.error(f'Line {line_num}: Error parsing line: {e} - {line[:50]}...')
                stats['skipped_error'] += 1

    logger.info(f'2024.txt parsed: {stats["parsed"]} transactions, {stats["skipped_zero"]} zero amounts, {stats["skipped_error"]} errors')
    return transactions, stats


def parse_2025_file(file_path: str, verbose: bool = False) -> Tuple[List[Transaction], Dict[str, int]]:
    """
    Parse 2025.txt (has date column)

    Format: 월<TAB>날짜<TAB>카테고리<TAB>내역<TAB>금액
    Example: 1	2025.01.01	식비	사계절반찬	₩139,800

    Args:
        file_path: Path to 2025.txt
        verbose: Enable verbose logging

    Returns:
        Tuple of (transactions: List[Transaction], stats: Dict[str, int])
    """
    transactions = []
    stats = {
        'total_lines': 0,
        'parsed': 0,
        'skipped_zero': 0,
        'skipped_empty_merchant': 0,
        'skipped_error': 0,
        'date_fallback': 0
    }

    logger.info(f'Parsing 2025.txt from: {file_path}')

    with open(file_path, 'r', encoding='utf-8') as f:
        for line_num, line in enumerate(f, start=1):
            stats['total_lines'] += 1
            line = line.strip()

            if not line:
                continue

            try:
                # Split by tab
                parts = line.split('\t')
                if len(parts) != 5:
                    logger.warning(f'Line {line_num}: Wrong number of fields ({len(parts)}), skipping: {line[:50]}...')
                    stats['skipped_error'] += 1
                    continue

                month_col, date_col, category, merchant, amount_str = parts

                # Extract month (simple integer, e.g., "1" → month=1)
                try:
                    month = int(month_col.strip())
                except ValueError:
                    logger.warning(f'Line {line_num}: Cannot parse month from: {month_col}')
                    stats['skipped_error'] += 1
                    continue

                # Handle date column
                if date_col and date_col.strip() and date_col.strip() != '':
                    # Use provided date
                    date_str = date_col.strip()
                else:
                    # Fallback to 1st of month
                    date_str = f'2025.{month:02d}.01'
                    stats['date_fallback'] += 1
                    if verbose:
                        logger.debug(f'Line {line_num}: Empty date, using fallback: {date_str}')

                # Parse amount
                amount = parse_amount(amount_str)

                # Skip zero amounts
                if amount == 0:
                    if verbose:
                        logger.debug(f'Line {line_num}: Skipping zero amount: {merchant}')
                    stats['skipped_zero'] += 1
                    continue

                # Skip empty merchant names
                if not merchant or merchant.strip() == '':
                    logger.warning(f'Line {line_num}: Empty merchant name, skipping')
                    stats['skipped_empty_merchant'] += 1
                    continue

                # Default empty category to "기타"
                if not category or category.strip() == '':
                    category = '기타'

                # Extract month string for Transaction
                month_str = f'{month:02d}'

                # Create Transaction
                txn = Transaction(
                    month=month_str,
                    date=date_str,
                    category=category.strip(),
                    item=merchant.strip(),
                    amount=amount,
                    source=INSTITUTION_NAME,
                    installment_months=None,
                    installment_current=None,
                    original_amount=None,
                    file_id=None,
                    row_number_in_file=None
                )

                transactions.append(txn)
                stats['parsed'] += 1

                if verbose:
                    logger.debug(f'Line {line_num}: Parsed {date_str} {merchant.strip()} {amount}원')

            except Exception as e:
                logger.error(f'Line {line_num}: Error parsing line: {e} - {line[:50]}...')
                stats['skipped_error'] += 1

    logger.info(f'2025.txt parsed: {stats["parsed"]} transactions, {stats["skipped_zero"]} zero amounts, {stats["skipped_error"]} errors')
    return transactions, stats


def print_preview_summary(transactions: List[Transaction], stats_2024: Dict[str, int], stats_2025: Dict[str, int]):
    """
    Print summary for dry-run mode

    Args:
        transactions: List of all parsed transactions
        stats_2024: Statistics from 2024.txt parsing
        stats_2025: Statistics from 2025.txt parsing
    """
    print('\n' + '='*80)
    print('DRY-RUN PREVIEW - No data will be inserted to database')
    print('='*80)

    print(f'\n2024.txt Statistics:')
    print(f'  Total lines: {stats_2024["total_lines"]}')
    print(f'  Parsed: {stats_2024["parsed"]}')
    print(f'  Skipped (zero amount): {stats_2024["skipped_zero"]}')
    print(f'  Skipped (empty merchant): {stats_2024["skipped_empty_merchant"]}')
    print(f'  Skipped (errors): {stats_2024["skipped_error"]}')

    print(f'\n2025.txt Statistics:')
    print(f'  Total lines: {stats_2025["total_lines"]}')
    print(f'  Parsed: {stats_2025["parsed"]}')
    print(f'  Date fallbacks: {stats_2025.get("date_fallback", 0)}')
    print(f'  Skipped (zero amount): {stats_2025["skipped_zero"]}')
    print(f'  Skipped (empty merchant): {stats_2025["skipped_empty_merchant"]}')
    print(f'  Skipped (errors): {stats_2025["skipped_error"]}')

    print(f'\nTotal Transactions Ready for Import: {len(transactions)}')

    # Show sample transactions
    if transactions:
        print(f'\nSample Transactions (first 10):')
        print(f'{'Date':<12} {'Category':<20} {'Merchant':<30} {'Amount':>12}')
        print('-'*80)
        for txn in transactions[:10]:
            print(f'{txn.date:<12} {txn.category:<20} {txn.item[:28]:<30} {txn.amount:>12,}원')

        if len(transactions) > 10:
            print(f'... and {len(transactions) - 10} more transactions')

    # Category breakdown
    category_counts = {}
    category_amounts = {}
    for txn in transactions:
        category_counts[txn.category] = category_counts.get(txn.category, 0) + 1
        category_amounts[txn.category] = category_amounts.get(txn.category, 0) + txn.amount

    print(f'\nCategory Breakdown:')
    print(f'{'Category':<20} {'Count':>8} {'Total Amount':>15}')
    print('-'*50)
    for cat in sorted(category_counts.keys()):
        print(f'{cat:<20} {category_counts[cat]:>8} {category_amounts[cat]:>15,}원')

    print('\nTo actually import this data, run without --dry-run flag')
    print('='*80 + '\n')


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description='Import manual transaction data from 2024.txt and 2025.txt'
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
    file_2024_path = os.path.join(project_root, FILE_2024)
    file_2025_path = os.path.join(project_root, FILE_2025)

    # Check files exist
    if not os.path.exists(file_2024_path):
        logger.error(f'File not found: {file_2024_path}')
        return 1

    if not os.path.exists(file_2025_path):
        logger.error(f'File not found: {file_2025_path}')
        return 1

    # Parse files
    logger.info('Starting file parsing...')
    transactions_2024, stats_2024 = parse_2024_file(file_2024_path, verbose=args.verbose)
    transactions_2025, stats_2025 = parse_2025_file(file_2025_path, verbose=args.verbose)

    # Combine all transactions
    all_transactions = transactions_2024 + transactions_2025
    logger.info(f'Total transactions parsed: {len(all_transactions)}')

    # Dry-run mode
    if args.dry_run:
        print_preview_summary(all_transactions, stats_2024, stats_2025)
        return 0

    # Actually insert to database
    logger.info('Connecting to database...')
    conn = DatabaseConnection.get_instance()

    try:
        # Initialize repositories
        category_repo = CategoryRepository(conn)
        institution_repo = InstitutionRepository(conn)
        transaction_repo = TransactionRepository(conn, category_repo, institution_repo)

        # Ensure institution exists
        institution_id = institution_repo.get_or_create(INSTITUTION_NAME, 'PAY')
        logger.info(f'Using institution: {INSTITUTION_NAME} (id={institution_id})')

        # Batch insert
        logger.info(f'Inserting {len(all_transactions)} transactions...')
        inserted_count = transaction_repo.batch_insert(all_transactions)

        # Print summary
        print('\n' + '='*80)
        print('IMPORT COMPLETE')
        print('='*80)
        print(f'\n2024.txt: {stats_2024["parsed"]} parsed')
        print(f'  Skipped: {stats_2024["skipped_zero"]} zero amounts, {stats_2024["skipped_error"]} errors')
        print(f'\n2025.txt: {stats_2025["parsed"]} parsed')
        print(f'  Skipped: {stats_2025["skipped_zero"]} zero amounts, {stats_2025["skipped_error"]} errors')
        print(f'\nTotal parsed: {len(all_transactions)}')
        print(f'Total inserted: {inserted_count}')
        print(f'Duplicates skipped: {len(all_transactions) - inserted_count}')
        print('\n' + '='*80 + '\n')

        logger.info('Import completed successfully')
        return 0

    except Exception as e:
        logger.error(f'Import failed: {e}', exc_info=True)
        return 1

    finally:
        DatabaseConnection.close()


if __name__ == '__main__':
    sys.exit(main())
