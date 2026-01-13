#!/usr/bin/env python3
"""
Build merchant-category mapping table from historical text files.

Parses 2024.txt and 2025.txt to extract merchant-category mappings,
inserts them into category_merchant_mappings table, and updates
existing transactions that were categorized as "기타" (Other).
"""

import argparse
import re
import sqlite3
import sys
from collections import defaultdict
from pathlib import Path
from typing import Dict, List, Set, Tuple


def parse_2024_txt(file_path: Path, verbose: bool = False) -> Dict[str, str]:
    """
    Parse 2024.txt file format: 번호→월\t카테고리\t가맹점명\t금액

    Returns dict of {merchant_name: category_name}
    """
    mappings = {}

    with open(file_path, 'r', encoding='utf-8') as f:
        for line_num, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue

            parts = line.split('\t')
            if len(parts) < 4:
                if verbose:
                    print(f"  [SKIP] Line {line_num}: insufficient columns - {line[:60]}")
                continue

            # Extract: 번호→월, 카테고리, 가맹점명, 금액
            category = parts[1].strip()
            merchant = parts[2].strip()
            amount = parts[3].strip()

            # Skip if no merchant name or zero amount
            if not merchant or amount == '₩0':
                if verbose:
                    print(f"  [SKIP] Line {line_num}: empty merchant or ₩0 amount")
                continue

            # Skip if category is empty
            if not category:
                if verbose:
                    print(f"  [SKIP] Line {line_num}: empty category")
                continue

            # Store mapping (last occurrence wins if duplicates)
            mappings[merchant] = category

            if verbose and line_num <= 10:
                print(f"  Line {line_num}: {merchant} → {category}")

    return mappings


def parse_2025_txt(file_path: Path, verbose: bool = False) -> Dict[str, str]:
    """
    Parse 2025.txt file format: 번호\tyyyy.mm.dd\t카테고리\t가맹점명\t금액

    Returns dict of {merchant_name: category_name}
    """
    mappings = {}

    with open(file_path, 'r', encoding='utf-8') as f:
        for line_num, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue

            parts = line.split('\t')
            if len(parts) < 5:
                if verbose:
                    print(f"  [SKIP] Line {line_num}: insufficient columns - {line[:60]}")
                continue

            # Extract: 번호, 날짜, 카테고리, 가맹점명, 금액
            category = parts[2].strip()
            merchant = parts[3].strip()
            amount = parts[4].strip()

            # Skip if no merchant name or zero amount
            if not merchant or amount == '₩0':
                if verbose:
                    print(f"  [SKIP] Line {line_num}: empty merchant or ₩0 amount")
                continue

            # Skip if category is empty
            if not category:
                if verbose:
                    print(f"  [SKIP] Line {line_num}: empty category")
                continue

            # Store mapping (last occurrence wins if duplicates)
            mappings[merchant] = category

            if verbose and line_num <= 10:
                print(f"  Line {line_num}: {merchant} → {category}")

    return mappings


def get_category_id_map(conn: sqlite3.Connection) -> Dict[str, int]:
    """
    Get mapping of category name to category ID.

    Returns dict of {category_name: category_id}
    """
    cursor = conn.cursor()
    cursor.execute("SELECT id, name FROM categories")
    return {name: id for id, name in cursor.fetchall()}


def insert_mappings(
    conn: sqlite3.Connection,
    mappings: Dict[str, str],
    category_id_map: Dict[str, int],
    dry_run: bool = False,
    verbose: bool = False
) -> Tuple[int, int, List[str]]:
    """
    Insert merchant-category mappings into database.

    Returns (new_count, existing_count, unmapped_categories)
    """
    cursor = conn.cursor()

    # Get existing mappings (merchant_pattern + match_type combination)
    cursor.execute(
        "SELECT merchant_pattern, match_type FROM category_merchant_mappings"
    )
    existing_merchants = {(row[0], row[1]) for row in cursor.fetchall()}

    new_count = 0
    existing_count = 0
    unmapped_categories = []

    for merchant, category in sorted(mappings.items()):
        # Check if category exists in database
        if category not in category_id_map:
            unmapped_categories.append(f"{merchant} → {category}")
            if verbose:
                print(f"  [UNMAPPED CATEGORY] {merchant} → {category}")
            continue

        category_id = category_id_map[category]

        # Check if exact match already exists
        if (merchant, 'exact') in existing_merchants:
            existing_count += 1
            if verbose:
                print(f"  [EXISTS] {merchant} → {category}")
        else:
            if not dry_run:
                cursor.execute(
                    """
                    INSERT OR IGNORE INTO category_merchant_mappings
                    (merchant_pattern, category_id, match_type, confidence, source, created_at, updated_at)
                    VALUES (?, ?, 'exact', 100, 'imported_2024_2025', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                    """,
                    (merchant, category_id)
                )
            new_count += 1
            if verbose:
                print(f"  [NEW] {merchant} → {category}")

    if not dry_run:
        conn.commit()

    return new_count, existing_count, unmapped_categories


def update_transactions(
    conn: sqlite3.Connection,
    dry_run: bool = False,
    verbose: bool = False
) -> Tuple[int, int]:
    """
    Update transactions from "기타" to proper categories based on mappings.

    Returns (updated_count, still_gita_count)
    """
    cursor = conn.cursor()

    # Get "기타" category ID
    cursor.execute("SELECT id FROM categories WHERE name = '기타'")
    result = cursor.fetchone()
    if not result:
        print("Warning: '기타' category not found in database")
        return 0, 0

    gita_category_id = result[0]

    # Count transactions that will be updated (exact match only)
    cursor.execute(
        """
        SELECT COUNT(*) FROM transactions t
        WHERE t.category_id = ?
          AND EXISTS (
              SELECT 1 FROM category_merchant_mappings cmm
              WHERE cmm.merchant_pattern = t.merchant_name
              AND cmm.match_type = 'exact'
          )
        """,
        (gita_category_id,)
    )
    will_update = cursor.fetchone()[0]

    # Count transactions that will remain as "기타"
    cursor.execute(
        """
        SELECT COUNT(*) FROM transactions t
        WHERE t.category_id = ?
          AND NOT EXISTS (
              SELECT 1 FROM category_merchant_mappings cmm
              WHERE cmm.merchant_pattern = t.merchant_name
              AND cmm.match_type = 'exact'
          )
        """,
        (gita_category_id,)
    )
    will_remain = cursor.fetchone()[0]

    if verbose:
        print(f"\nTransactions to update: {will_update}")
        print(f"Transactions remaining as '기타': {will_remain}")

        if will_update > 0:
            cursor.execute(
                """
                SELECT DISTINCT t.merchant_name, c.name
                FROM transactions t
                JOIN category_merchant_mappings cmm
                  ON cmm.merchant_pattern = t.merchant_name
                  AND cmm.match_type = 'exact'
                JOIN categories c ON cmm.category_id = c.id
                WHERE t.category_id = ?
                ORDER BY t.merchant_name
                """,
                (gita_category_id,)
            )
            print("\nTransactions being remapped:")
            for merchant, new_category in cursor.fetchall():
                print(f"  {merchant} → {new_category}")

    if not dry_run and will_update > 0:
        cursor.execute(
            """
            UPDATE transactions
            SET category_id = (
                SELECT cmm.category_id
                FROM category_merchant_mappings cmm
                WHERE cmm.merchant_pattern = transactions.merchant_name
                AND cmm.match_type = 'exact'
                LIMIT 1
            ),
            updated_at = CURRENT_TIMESTAMP
            WHERE category_id = ?
              AND EXISTS (
                  SELECT 1 FROM category_merchant_mappings cmm
                  WHERE cmm.merchant_pattern = transactions.merchant_name
                  AND cmm.match_type = 'exact'
              )
            """,
            (gita_category_id,)
        )
        conn.commit()

    return will_update, will_remain


def get_category_distribution(conn: sqlite3.Connection) -> List[Tuple[str, int, float]]:
    """
    Get category distribution of all transactions.

    Returns list of (category_name, count, percentage)
    """
    cursor = conn.cursor()
    cursor.execute(
        """
        SELECT
            c.name,
            COUNT(*) as count,
            COUNT(*) * 100.0 / (SELECT COUNT(*) FROM transactions) as percentage
        FROM transactions t
        JOIN categories c ON t.category_id = c.id
        GROUP BY c.name
        ORDER BY count DESC
        """
    )
    return cursor.fetchall()


def main():
    parser = argparse.ArgumentParser(
        description='Build merchant-category mappings from historical txt files'
    )
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Show what would be done without making changes'
    )
    parser.add_argument(
        '--verbose',
        action='store_true',
        help='Show detailed parsing output'
    )
    parser.add_argument(
        '--db-path',
        type=Path,
        default=Path('data/expense_tracker.db'),
        help='Path to SQLite database (default: data/expense_tracker.db)'
    )

    args = parser.parse_args()

    # File paths
    file_2024 = Path('2024.txt')
    file_2025 = Path('2025.txt')

    # Check files exist
    if not file_2024.exists():
        print(f"Error: {file_2024} not found")
        sys.exit(1)

    if not file_2025.exists():
        print(f"Error: {file_2025} not found")
        sys.exit(1)

    if not args.db_path.exists():
        print(f"Error: Database {args.db_path} not found")
        sys.exit(1)

    print("=" * 80)
    print("Building Merchant-Category Mappings from Historical Data")
    print("=" * 80)

    if args.dry_run:
        print("\n[DRY RUN MODE - No changes will be made]\n")

    # Parse files
    print(f"\nParsing {file_2024}...")
    mappings_2024 = parse_2024_txt(file_2024, verbose=args.verbose)
    print(f"  Found {len(mappings_2024)} unique merchants")

    print(f"\nParsing {file_2025}...")
    mappings_2025 = parse_2025_txt(file_2025, verbose=args.verbose)
    print(f"  Found {len(mappings_2025)} unique merchants")

    # Combine mappings (2025 takes precedence over 2024)
    all_mappings = {**mappings_2024, **mappings_2025}
    print(f"\nTotal unique merchant-category pairs: {len(all_mappings)}")

    # Connect to database
    conn = sqlite3.connect(args.db_path)

    try:
        # Get category ID mapping
        category_id_map = get_category_id_map(conn)
        print(f"Database has {len(category_id_map)} categories")

        # Get distribution before update
        print("\nCategory distribution BEFORE update:")
        dist_before = get_category_distribution(conn)
        for name, count, pct in dist_before[:10]:  # Top 10
            print(f"  {name}: {count}건 ({pct:.1f}%)")
        if len(dist_before) > 10:
            print(f"  ... and {len(dist_before) - 10} more categories")

        # Insert mappings
        print("\n" + "-" * 80)
        print("Database insertion:")
        new_count, existing_count, unmapped = insert_mappings(
            conn, all_mappings, category_id_map,
            dry_run=args.dry_run, verbose=args.verbose
        )
        print(f"  New mappings inserted: {new_count}")
        print(f"  Existing mappings skipped: {existing_count}")

        if unmapped:
            print(f"\n  WARNING: {len(unmapped)} merchants have unmapped categories:")
            for mapping in unmapped[:10]:  # Show first 10
                print(f"    {mapping}")
            if len(unmapped) > 10:
                print(f"    ... and {len(unmapped) - 10} more")

        # Get total mappings
        cursor = conn.cursor()
        cursor.execute("SELECT COUNT(*) FROM category_merchant_mappings")
        total_mappings = cursor.fetchone()[0]
        print(f"  Total mappings in database: {total_mappings}")

        # Update transactions
        print("\n" + "-" * 80)
        print("Transaction updates:")
        updated_count, still_gita_count = update_transactions(
            conn, dry_run=args.dry_run, verbose=args.verbose
        )
        print(f"  Transactions remapped: {updated_count}")
        print(f"  Transactions still '기타': {still_gita_count}")

        # Get distribution after update
        print("\n" + "-" * 80)
        print("Category distribution AFTER update:")
        dist_after = get_category_distribution(conn)
        for name, count, pct in dist_after[:15]:  # Top 15
            print(f"  {name}: {count}건 ({pct:.1f}%)")

        # Calculate categorization accuracy
        cursor.execute("SELECT COUNT(*) FROM transactions")
        total_transactions = cursor.fetchone()[0]
        properly_categorized = total_transactions - still_gita_count
        accuracy = (properly_categorized / total_transactions * 100) if total_transactions > 0 else 0

        print("\n" + "=" * 80)
        print(f"Categorization accuracy: {accuracy:.1f}% ({properly_categorized}/{total_transactions} transactions)")
        print("=" * 80)

        if args.dry_run:
            print("\n[DRY RUN COMPLETED - No changes were made]")
        else:
            print("\n✓ Successfully updated database")

    finally:
        conn.close()


if __name__ == '__main__':
    main()
