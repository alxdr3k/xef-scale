#!/usr/bin/env python3
"""
Re-categorize transactions marked as '기타' using the category-merchant mapping table.

This script:
1. Finds all transactions where category='기타'
2. Attempts to re-categorize using the updated CategoryMatcher (with database mappings)
3. Updates transactions in batch
4. Provides detailed statistics

Usage:
    python scripts/update_gita_categories.py --dry-run  # Preview only
    python scripts/update_gita_categories.py             # Actually update
    python scripts/update_gita_categories.py --verbose   # Detailed logging
"""

import sys
import os
import argparse
import logging
from typing import List, Dict, Tuple

# Add project root to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from src.db.connection import DatabaseConnection
from src.db.repository import (
    CategoryRepository,
    TransactionRepository,
    CategoryMerchantMappingRepository
)
from src.category_matcher import CategoryMatcher


def setup_logging(verbose: bool = False):
    """Configure logging"""
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format='%(asctime)s - %(levelname)s - %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )


def get_gita_transactions() -> List[Dict]:
    """
    Get all transactions with category='기타'

    Returns:
        List of transaction dicts with id, merchant_name, amount, transaction_date
    """
    conn = DatabaseConnection.get_instance()
    category_repo = CategoryRepository(conn)

    # Get '기타' category id
    gita_category = category_repo.get_by_name('기타')
    if not gita_category:
        logging.error("'기타' category not found in database")
        return []

    gita_id = gita_category['id']

    # Query transactions
    cursor = conn.cursor()
    cursor.execute("""
        SELECT id, merchant_name, amount, transaction_date
        FROM transactions
        WHERE category_id = ?
        ORDER BY transaction_date DESC
    """, (gita_id,))

    transactions = []
    for row in cursor.fetchall():
        transactions.append({
            'id': row[0],
            'merchant_name': row[1],
            'amount': row[2],
            'transaction_date': row[3]
        })

    return transactions


def re_categorize_transactions(
    transactions: List[Dict],
    matcher: CategoryMatcher,
    category_repo: CategoryRepository
) -> Tuple[List[Dict], Dict[str, int]]:
    """
    Re-categorize transactions using CategoryMatcher.

    Args:
        transactions: List of transaction dicts
        matcher: CategoryMatcher instance (with database repos)
        category_repo: CategoryRepository for lookups

    Returns:
        (updates, stats) where:
        - updates: List of dicts with {id, old_category_id, new_category_id}
        - stats: Dict with counts by category
    """
    updates = []
    stats = {}

    for txn in transactions:
        merchant_name = txn['merchant_name']
        new_category_name = matcher.get_category(merchant_name)

        # Track stats
        stats[new_category_name] = stats.get(new_category_name, 0) + 1

        # Skip if still '기타'
        if new_category_name == '기타':
            continue

        # Get new category_id
        new_category = category_repo.get_by_name(new_category_name)
        if not new_category:
            logging.warning(f"Category '{new_category_name}' not found for merchant '{merchant_name}'")
            continue

        updates.append({
            'id': txn['id'],
            'merchant_name': merchant_name,
            'new_category_id': new_category['id'],
            'new_category_name': new_category_name
        })

    return updates, stats


def apply_updates(updates: List[Dict]) -> int:
    """
    Apply category updates to transactions.

    Args:
        updates: List of update dicts with id, new_category_id

    Returns:
        Number of transactions updated
    """
    conn = DatabaseConnection.get_instance()
    cursor = conn.cursor()

    for update in updates:
        cursor.execute("""
            UPDATE transactions
            SET category_id = ?, updated_at = CURRENT_TIMESTAMP
            WHERE id = ?
        """, (update['new_category_id'], update['id']))

    conn.commit()
    return len(updates)


def print_preview(transactions: List[Dict], updates: List[Dict], stats: Dict[str, int]):
    """Print preview summary for dry-run mode"""
    print("\n" + "="*60)
    print(f"PREVIEW: Re-categorization of '기타' Transactions")
    print("="*60)
    print(f"\nTotal '기타' transactions found: {len(transactions)}")
    print(f"Transactions that can be re-categorized: {len(updates)}")
    print(f"Transactions remaining as '기타': {len(transactions) - len(updates)}")

    print("\n--- New Category Distribution ---")
    for category, count in sorted(stats.items(), key=lambda x: x[1], reverse=True):
        print(f"  {category:30} {count:>4} transactions")

    if updates:
        print("\n--- Sample Updates (first 10) ---")
        for update in updates[:10]:
            print(f"  {update['merchant_name']:30} → {update['new_category_name']}")

        if len(updates) > 10:
            print(f"  ... and {len(updates) - 10} more")


def main():
    parser = argparse.ArgumentParser(
        description='Re-categorize transactions marked as 기타 using mapping table'
    )
    parser.add_argument('--dry-run', action='store_true',
                       help='Preview changes without updating database')
    parser.add_argument('--verbose', action='store_true',
                       help='Enable verbose logging')
    args = parser.parse_args()

    setup_logging(args.verbose)

    logging.info("Starting re-categorization of '기타' transactions")

    # Initialize repositories
    conn = DatabaseConnection.get_instance()
    category_repo = CategoryRepository(conn)
    mapping_repo = CategoryMerchantMappingRepository(conn)

    # Create CategoryMatcher with database support
    matcher = CategoryMatcher(mapping_repo=mapping_repo, category_repo=category_repo)

    # Get '기타' transactions
    logging.info("Fetching transactions with category='기타'")
    transactions = get_gita_transactions()
    logging.info(f"Found {len(transactions)} '기타' transactions")

    if not transactions:
        logging.info("No '기타' transactions to update")
        print("\n✓ No '기타' transactions found. Nothing to update.")
        return

    # Re-categorize
    logging.info("Re-categorizing transactions using mapping table")
    updates, stats = re_categorize_transactions(transactions, matcher, category_repo)

    # Preview or apply
    if args.dry_run:
        print_preview(transactions, updates, stats)
        print("\n✓ Dry-run complete. No changes made to database.")
    else:
        print_preview(transactions, updates, stats)

        if not updates:
            print("\n✓ No transactions can be re-categorized. All remain as '기타'.")
            return

        print("\n" + "="*60)
        print("Applying updates to database...")
        updated_count = apply_updates(updates)
        logging.info(f"Successfully updated {updated_count} transactions")
        print(f"✓ Updated {updated_count} transactions")
        print(f"✓ {len(transactions) - updated_count} transactions remain as '기타'")


if __name__ == '__main__':
    main()
