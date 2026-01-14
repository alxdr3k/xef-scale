#!/usr/bin/env python3
"""Test multi-model fallback strategy with real transactions."""

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

from src.db.connection import DatabaseConnection
from src.db.repository import CategoryRepository, CategoryMerchantMappingRepository
from src.config import GEMINI_API_KEY
from src.gemini_client import GeminiClient


def main():
    print("="*80)
    print("MULTI-MODEL FALLBACK TEST")
    print("="*80)

    # Initialize
    conn = DatabaseConnection.get_instance()
    category_repo = CategoryRepository(conn)
    mapping_repo = CategoryMerchantMappingRepository(conn)

    categories = category_repo.get_all()
    valid_category_names = [cat['name'] for cat in categories]

    gemini_client = GeminiClient(
        api_key=GEMINI_API_KEY,
        valid_categories=valid_category_names
    )

    # Get uncategorized transactions
    cursor = conn.cursor()
    cursor.execute("""
        SELECT t.merchant_name
        FROM transactions t
        JOIN categories c ON t.category_id = c.id
        WHERE c.name = '기타'
          AND t.deleted_at IS NULL
          AND t.merchant_name IS NOT NULL
        LIMIT 10  -- Test with 10 first
    """)

    merchants = [row[0] for row in cursor.fetchall()]
    print(f"\nTesting with {len(merchants)} merchants\n")

    # Test categorization
    results = {'success': 0, 'failed': 0}

    for merchant in merchants:
        category = gemini_client.categorize_merchant(merchant)
        if category and category != '기타':
            results['success'] += 1
            print(f"✓ {merchant[:50]} → {category}")
        else:
            results['failed'] += 1
            print(f"✗ {merchant[:50]} → (no category)")

    # Print model statistics
    print("\n" + "="*80)
    print("MODEL USAGE STATISTICS")
    print("="*80)

    stats = gemini_client.get_model_stats()
    for model, counts in stats.items():
        total = sum(counts.values())
        if total > 0:
            print(f"\n{model}:")
            print(f"  Success: {counts['success']}")
            print(f"  Failed: {counts['failed']}")
            print(f"  Rate Limited: {counts['rate_limited']}")

    print(f"\n\nOverall:")
    print(f"  Categorized: {results['success']}/{len(merchants)}")
    print(f"  Failed: {results['failed']}/{len(merchants)}")
    print("="*80)


if __name__ == '__main__':
    main()
