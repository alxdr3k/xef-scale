"""
CategoryMatcher helper for auto-categorizing transactions.
Uses keyword matching based on merchant names with Korean text support.
"""

from src.config import CATEGORY_RULES


class CategoryMatcher:
    """
    Auto-categorizes transactions based on merchant names using keyword matching.

    Loads category rules from config.py and matches merchant names against keywords.
    Supports Korean text processing with space stripping and case-insensitive matching.
    """

    def __init__(self):
        """Initialize CategoryMatcher with rules from config."""
        self.rules = CATEGORY_RULES.copy()

    def get_category(self, item_name: str) -> str:
        """
        Categorize transaction based on merchant name.

        Searches the merchant name for keywords defined in category rules.
        Processing includes space removal and case-insensitive matching.

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
        """
        # Normalize: remove spaces and convert to lowercase for matching
        name = item_name.replace(' ', '').lower()

        # Search through all category rules
        for category, keywords in self.rules.items():
            for keyword in keywords:
                if keyword.lower() in name:
                    return category

        # Default category if no match found
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
