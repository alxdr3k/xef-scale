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
    2. Gemini API (LLM categorization) - Semantic matching with auto-caching
    3. Keyword rules from config.py - Legacy fallback
    4. Default to '기타' if no match found

    Supports database-driven mode, Gemini API mode, and legacy keyword-only mode
    for backward compatibility with existing code.
    """

    def __init__(
        self,
        mapping_repo: Optional[CategoryMerchantMappingRepository] = None,
        category_repo: Optional[CategoryRepository] = None,
        gemini_client: Optional['GeminiClient'] = None
    ):
        """
        Initialize CategoryMatcher with optional Gemini API support.

        Args:
            mapping_repo: Optional repository for merchant mappings
            category_repo: Optional repository for category lookups
            gemini_client: Optional Gemini API client for LLM categorization

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
            - When gemini_client is None, Gemini tier is skipped (backward compatible)
            - When repos are None, operates in legacy mode (keyword rules only)
            - Gemini responses auto-saved to database when repos provided
        """
        self.mapping_repo = mapping_repo
        self.category_repo = category_repo
        self.gemini_client = gemini_client
        self.rules = CATEGORY_RULES.copy()
        self.logger = logging.getLogger(__name__)

        # Log initialization mode
        if self.gemini_client:
            self.logger.debug('CategoryMatcher initialized with Gemini API support')
        elif self.mapping_repo and self.category_repo:
            self.logger.debug('CategoryMatcher initialized in database mode (no Gemini)')
        else:
            self.logger.debug('CategoryMatcher initialized in legacy mode (keyword rules only)')

    def get_category(self, item_name: str) -> str:
        """
        Categorize transaction based on merchant name.

        Priority (UPDATED):
        1. Database mapping (exact match)
        2. Gemini API (LLM categorization) - NEW
        3. Keyword rules from config.py
        4. Default to '기타'

        Args:
            item_name: Merchant name (Korean text supported)

        Returns:
            Category string or '기타' if no match

        Examples:
            >>> matcher = CategoryMatcher()
            >>> matcher.get_category('스타벅스 식당')
            '식비'
            >>> matcher.get_category('GS주유소')
            '교통'
            >>> matcher.get_category('알수없음')
            '기타'

        Notes:
            - Database exact match happens first if repositories available
            - Gemini API provides semantic matching for new merchants
            - Gemini responses auto-saved to database for caching
            - Falls back to keyword rules if Gemini fails
            - Handles empty merchant names gracefully (returns '기타')
        """
        # Edge case: empty merchant name
        if not item_name or not item_name.strip():
            self.logger.debug('Empty merchant name, returning default category')
            return '기타'

        # Step 1: Try database exact match
        if self.mapping_repo and self.category_repo:
            try:
                category_id = self.mapping_repo.get_category_by_merchant(item_name)
                if category_id:
                    category = self.category_repo.get_by_id(category_id)
                    if category:
                        self.logger.debug(
                            f'Database exact match: {item_name} → {category["name"]} (id={category_id})'
                        )
                        return category['name']
            except Exception as e:
                self.logger.error(f'Database lookup failed for "{item_name}": {e}. Continuing to Gemini.')

        # Step 2: Try Gemini API (NEW)
        if self.gemini_client:
            try:
                gemini_category = self.gemini_client.categorize_merchant(item_name)
                if gemini_category:
                    self.logger.debug(f'Gemini match: {item_name} → {gemini_category}')

                    # Auto-save to database for future caching
                    if self.mapping_repo and self.category_repo:
                        self._save_gemini_mapping(item_name, gemini_category)

                    return gemini_category
            except Exception as e:
                self.logger.error(f'Gemini API failed for "{item_name}": {e}. Falling back to keywords.')

        # Step 3: Fall back to keyword rules from config
        name = item_name.replace(' ', '').lower()

        for category, keywords in self.rules.items():
            for keyword in keywords:
                if keyword.lower() in name:
                    self.logger.debug(f'Keyword match: {item_name} → {category} (keyword: {keyword})')
                    return category

        # Step 4: Default category if no match found
        self.logger.debug(f'No match found for merchant: {item_name}, returning default category')
        return '기타'

    def _save_gemini_mapping(self, merchant_name: str, category_name: str):
        """
        Save Gemini API response to database for caching.

        Creates mapping with source='gemini' and confidence=95 to distinguish
        from manual mappings (confidence=100) and legacy imports.

        Args:
            merchant_name: Merchant name categorized by Gemini
            category_name: Category returned by Gemini

        Notes:
            - Uses INSERT OR IGNORE to handle duplicates gracefully
            - Confidence=95: High but not 100 (reserves 100 for manual)
            - Match type='exact' for O(1) future lookups
            - Errors logged but don't interrupt transaction processing
        """
        try:
            # Get category_id from name
            category = self.category_repo.get_by_name(category_name)
            if not category:
                self.logger.warning(f'Category "{category_name}" not found in database, cannot save mapping')
                return

            category_id = category['id']

            # Save mapping to database
            self.mapping_repo.add_mapping(
                category_id=category_id,
                merchant_pattern=merchant_name,
                match_type='exact',
                confidence=95,  # High but not 100 (reserves 100 for manual)
                source='gemini'
            )

            self.logger.info(
                f'Saved Gemini mapping: "{merchant_name}" → {category_name} (id={category_id})'
            )
        except Exception as e:
            # Don't fail transaction processing on cache save errors
            self.logger.error(
                f'Failed to save Gemini mapping for "{merchant_name}": {e}. '
                f'Transaction processing continues.'
            )

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
