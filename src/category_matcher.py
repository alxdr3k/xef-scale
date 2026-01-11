"""
CategoryMatcher helper for auto-categorizing transactions.
Uses database-driven merchant mapping with keyword fallback for backward compatibility.
"""

import logging
from typing import Optional
from src.config import CATEGORY_RULES
from src.db.repository import CategoryMerchantMappingRepository, CategoryRepository


class CategoryMatcher:
    """
    Auto-categorizes transactions based on merchant names.

    Priority system:
    1. Database mapping (exact match) - O(1) indexed lookup
    2. Database mapping (partial match) - LIKE query for variations
    3. Keyword rules from config.py - Legacy fallback
    4. Default to '기타' if no match found

    Supports both database-driven mode and legacy keyword-only mode
    for backward compatibility with existing code.
    """

    def __init__(
        self,
        mapping_repo: Optional[CategoryMerchantMappingRepository] = None,
        category_repo: Optional[CategoryRepository] = None
    ):
        """
        Initialize CategoryMatcher with optional database repositories.

        Args:
            mapping_repo: Optional repository for merchant mappings (database-driven)
            category_repo: Optional repository for category lookups

        Examples:
            >>> # Legacy mode (keyword rules only)
            >>> matcher = CategoryMatcher()
            >>> category = matcher.get_category('스타벅스')
            >>> # Database mode (with repository injection)
            >>> conn = DatabaseConnection.get_instance()
            >>> mapping_repo = CategoryMerchantMappingRepository(conn)
            >>> category_repo = CategoryRepository(conn)
            >>> matcher = CategoryMatcher(mapping_repo=mapping_repo, category_repo=category_repo)
            >>> category = matcher.get_category('스타벅스')

        Notes:
            - When repos are None, operates in legacy mode (keyword rules only)
            - When repos provided, uses database-first strategy with keyword fallback
            - Backward compatible with existing code
        """
        self.mapping_repo = mapping_repo
        self.category_repo = category_repo
        self.rules = CATEGORY_RULES.copy()
        self.logger = logging.getLogger(__name__)

        # Log initialization mode
        if self.mapping_repo and self.category_repo:
            self.logger.debug('CategoryMatcher initialized in database mode')
        else:
            self.logger.debug('CategoryMatcher initialized in legacy mode (keyword rules only)')

    def get_category(self, item_name: str) -> str:
        """
        Categorize transaction based on merchant name.

        Priority:
        1. Database mapping (exact match)
        2. Database mapping (partial match)
        3. Keyword rules from config.py
        4. Default to '기타'

        Args:
            item_name: Merchant name (Korean text supported)

        Returns:
            Category string (e.g., '식비', '교통', '통신') or '기타' if no match

        Examples:
            >>> matcher = CategoryMatcher()
            >>> matcher.get_category('스타벅스 식당')
            '식비'
            >>> matcher.get_category('GS주유소')
            '교통'
            >>> matcher.get_category('알수없음')
            '기타'

        Notes:
            - Database lookup happens first if repositories are available
            - Falls back to keyword rules if database lookup fails
            - Handles empty merchant names gracefully (returns '기타')
            - Database errors are caught and logged, then falls back to keyword rules
        """
        # Edge case: empty merchant name
        if not item_name or not item_name.strip():
            self.logger.debug('Empty merchant name, returning default category')
            return '기타'

        # Step 1: Try database mapping if available
        if self.mapping_repo and self.category_repo:
            try:
                category_id = self.mapping_repo.get_category_by_merchant(item_name)
                if category_id:
                    category = self.category_repo.get_by_id(category_id)
                    if category:
                        self.logger.debug(
                            f'Database match: {item_name} -> {category["name"]} (id={category_id})'
                        )
                        return category['name']
                    else:
                        # Category ID found but category doesn't exist (data inconsistency)
                        self.logger.warning(
                            f'Category ID {category_id} found for merchant "{item_name}" '
                            f'but category not in database. Falling back to keyword rules.'
                        )
            except Exception as e:
                # Database error: log and fall back to keyword rules
                self.logger.error(
                    f'Database lookup failed for merchant "{item_name}": {e}. '
                    f'Falling back to keyword rules.'
                )

        # Step 2: Fall back to keyword rules from config
        name = item_name.replace(' ', '').lower()

        for category, keywords in self.rules.items():
            for keyword in keywords:
                if keyword.lower() in name:
                    self.logger.debug(f'Keyword match: {item_name} -> {category} (keyword: {keyword})')
                    return category

        # Step 3: Default category if no match found
        self.logger.debug(f'No match found for merchant: {item_name}, returning default category')
        return '기타'

    def add_rule(self, category: str, keyword: str):
        """
        Add new categorization rule dynamically.

        Useful for learning new patterns and expanding categorization rules.

        Args:
            category: Category name (e.g., '식비', '교통')
            keyword: Keyword to match in merchant names

        Examples:
            >>> matcher = CategoryMatcher()
            >>> matcher.add_rule('의료', '병원')
            >>> matcher.get_category('서울병원')
            '의료'
        """
        if category not in self.rules:
            self.rules[category] = []
        self.rules[category].append(keyword)
