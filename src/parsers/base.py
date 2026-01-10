"""
Abstract base class for statement parsers.
Defines the Strategy Pattern for institution-specific parser implementations.
"""

from abc import ABC, abstractmethod
from typing import List
from src.models import Transaction, ParseResult
from src.category_matcher import CategoryMatcher


class StatementParser(ABC):
    """
    Abstract base class for all institution-specific parsers.

    Uses the Strategy Pattern to allow different parsing implementations
    for different financial institutions. Each parser has access to a
    shared CategoryMatcher instance for transaction categorization.

    Attributes:
        matcher: CategoryMatcher instance for auto-categorizing transactions
    """

    def __init__(self):
        """Initialize parser with CategoryMatcher instance."""
        self.matcher = CategoryMatcher()

    @abstractmethod
    def parse(self, input_data: any) -> ParseResult:
        """
        Parse statement file and return ParseResult with transactions and skipped rows.

        This method must be implemented by all concrete parser subclasses.
        The implementation should handle institution-specific file formats
        (Excel, PDF, CSV, etc.) and extract transaction data.

        Args:
            input_data: File path (str) or raw content depending on implementation

        Returns:
            ParseResult containing:
                - transactions: List of successfully parsed Transaction objects
                - skipped: List of SkippedTransaction objects for rows that couldn't be parsed
                - total_rows_scanned: Total number of rows processed
                - parser_type: Identifier for the parser (e.g., 'HANA', 'SHINHAN')

        Raises:
            ParseError: If file cannot be parsed or has invalid format
            FileNotFoundError: If file path is invalid
            ValueError: If data format is incorrect

        Examples:
            >>> class HanaParser(StatementParser):
            ...     def parse(self, input_data):
            ...         # Implementation specific to Hana Card
            ...         return ParseResult(transactions=[Transaction(...)], skipped=[], ...)
            >>> parser = HanaParser()
            >>> result = parser.parse('statement.xlsx')
            >>> print(f"Parsed {len(result.transactions)} transactions, skipped {len(result.skipped)}")
        """
        pass
