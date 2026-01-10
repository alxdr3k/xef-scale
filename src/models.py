"""
Data models for expense tracking system.
Contains Transaction dataclass for representing expense transactions.
"""

from dataclasses import dataclass
from typing import Dict, Optional


@dataclass
class Transaction:
    """
    Represents a single expense transaction.

    Attributes:
        month: Month in format 'mm'
        date: Date in format 'yyyy.mm.dd'
        category: Category (e.g., 식비/교통/통신)
        item: Merchant name
        amount: Amount in KRW (actual charged amount for this billing period)
        source: Institution name (bank/card)
        installment_months: Number of installment months (None for one-time payment)
        installment_current: Current installment number (None for one-time payment)
        original_amount: Original full amount (only for installment transactions)
        file_id: Internal file tracking ID (None for legacy transactions, auto-managed)
        row_number_in_file: Row number within source file (None for legacy transactions, auto-managed)
    """
    month: str
    date: str
    category: str
    item: str
    amount: int
    source: str
    installment_months: Optional[int] = None
    installment_current: Optional[int] = None
    original_amount: Optional[int] = None
    file_id: Optional[int] = None
    row_number_in_file: Optional[int] = None

    def to_dict(self) -> Dict[str, any]:
        """
        Convert transaction to dictionary with Korean column names for CSV serialization.

        Returns:
            Dictionary with Korean keys matching the CSV format
        """
        result = {
            '월': self.month,
            '날짜': self.date,
            '분류': self.category,
            '항목': self.item,
            '금액': self.amount,
            '은행/카드': self.source
        }

        # Add installment info if present
        if self.installment_months:
            result['할부개월'] = self.installment_months
            result['할부회차'] = self.installment_current
            result['원금액'] = self.original_amount

        return result

    def __str__(self) -> str:
        """
        Return readable string representation for logging.

        Returns:
            Formatted string with date, item, amount, and source
        """
        return f'{self.date} {self.item} {self.amount}원 ({self.source})'


@dataclass
class ProcessingResult:
    """
    Represents the result of file processing operation.

    Used by FileProcessor to communicate processing outcome to FileWatcher
    and other consumers. Provides structured error handling and status tracking.

    Attributes:
        status: Processing status ('success', 'duplicate', 'error')
        message: Human-readable message describing the outcome
        transaction_count: Number of transactions processed (0 for duplicate/error)
        file_id: Database ID of processed file (None for duplicate/error)
        file_hash: SHA256 hash of processed file (useful for duplicate identification)

    Examples:
        >>> # Successful processing
        >>> result = ProcessingResult(
        ...     status='success',
        ...     message='Processed 85 transactions from hana_statement.xls',
        ...     transaction_count=85,
        ...     file_id=1,
        ...     file_hash='abc123...'
        ... )
        >>> print(result.status)
        'success'

        >>> # Duplicate file detected
        >>> result = ProcessingResult(
        ...     status='duplicate',
        ...     message='Duplicate file detected, skipped processing',
        ...     transaction_count=0,
        ...     file_id=None,
        ...     file_hash='abc123...'
        ... )
        >>> print(result.status)
        'duplicate'

        >>> # Error during processing
        >>> result = ProcessingResult(
        ...     status='error',
        ...     message='Failed to parse file: invalid format',
        ...     transaction_count=0,
        ...     file_id=None,
        ...     file_hash=None
        ... )
        >>> print(result.status)
        'error'
    """
    status: str
    message: str
    transaction_count: int
    file_id: Optional[int] = None
    file_hash: Optional[str] = None

    def is_success(self) -> bool:
        """Check if processing was successful."""
        return self.status == 'success'

    def is_duplicate(self) -> bool:
        """Check if file was a duplicate."""
        return self.status == 'duplicate'

    def is_error(self) -> bool:
        """Check if processing failed with error."""
        return self.status == 'error'
