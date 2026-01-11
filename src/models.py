"""
Data models for expense tracking system.
Contains Transaction dataclass for representing expense transactions.
"""

from dataclasses import dataclass, field
from typing import Dict, Optional, List


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
        status: Processing status ('success', 'pending_confirmation', 'duplicate', 'error')
        message: Human-readable message describing the outcome
        transaction_count: Number of transactions processed (0 for duplicate/error)
        file_id: Database ID of processed file (None for duplicate/error)
        file_hash: SHA256 hash of processed file (useful for duplicate identification)
        transactions_pending: Number of transactions pending user confirmation (duplicate detection)
        session_id: Parsing session ID for tracking confirmation workflow

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

        >>> # Pending confirmation (duplicate transactions detected)
        >>> result = ProcessingResult(
        ...     status='pending_confirmation',
        ...     message='3 potential duplicates detected. 82 unique transactions inserted.',
        ...     transaction_count=82,
        ...     transactions_pending=3,
        ...     session_id=5,
        ...     file_id=1,
        ...     file_hash='abc123...'
        ... )
        >>> print(result.status)
        'pending_confirmation'

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
    transactions_pending: int = 0
    session_id: Optional[int] = None

    def is_success(self) -> bool:
        """Check if processing was successful."""
        return self.status == 'success'

    def is_duplicate(self) -> bool:
        """Check if file was a duplicate."""
        return self.status == 'duplicate'

    def is_error(self) -> bool:
        """Check if processing failed with error."""
        return self.status == 'error'

    def is_pending_confirmation(self) -> bool:
        """Check if processing has pending duplicate confirmations."""
        return self.status == 'pending_confirmation'


class SkipReason:
    """
    Constants for skip reasons during transaction parsing.

    Used by parsers to categorize why a transaction row was skipped.
    """
    ZERO_AMOUNT = 'zero_amount'
    INVALID_DATE = 'invalid_date'
    MISSING_MERCHANT = 'missing_merchant'
    MISSING_AMOUNT = 'missing_amount'
    INVALID_AMOUNT = 'invalid_amount'
    NON_DATA_ROW = 'non_data_row'
    PARSING_ERROR = 'parsing_error'
    EMPTY_ROW = 'empty_row'


@dataclass
class SkippedTransaction:
    """
    Represents a transaction that was skipped during parsing.

    Contains metadata about why the transaction could not be processed.
    Used for validation, reporting, and debugging.

    Attributes:
        row_number: Physical row number in source file
        skip_reason: Reason constant from SkipReason class
        transaction_date: Date if extractable (None otherwise)
        merchant_name: Merchant name if extractable (None otherwise)
        amount: Amount if extractable (None otherwise)
        original_amount: Original amount for installment transactions
        skip_details: Additional context about the skip
        column_data: Raw column values for debugging (optional)
    """
    row_number: int
    skip_reason: str
    transaction_date: Optional[str] = None
    merchant_name: Optional[str] = None
    amount: Optional[int] = None
    original_amount: Optional[int] = None
    skip_details: Optional[str] = None
    column_data: Optional[Dict] = None

    def to_dict(self) -> Dict:
        """Convert to dict for JSON serialization (API-friendly)."""
        return {
            'row_number': self.row_number,
            'skip_reason': self.skip_reason,
            'transaction_date': self.transaction_date,
            'merchant_name': self.merchant_name,
            'amount': self.amount,
            'original_amount': self.original_amount,
            'skip_details': self.skip_details,
            'column_data': self.column_data
        }


@dataclass
class ParseResult:
    """
    Enriched result from parser with both successful and skipped transactions.

    Replaces the simple List[Transaction] return type from parsers.
    Provides complete picture of what happened during parsing.

    Attributes:
        transactions: Successfully parsed transactions
        skipped: Skipped transactions with metadata
        total_rows_scanned: Total rows examined by parser
        parser_type: Parser identifier (e.g., 'HANA', 'TOSS')
    """
    transactions: List[Transaction] = field(default_factory=list)
    skipped: List[SkippedTransaction] = field(default_factory=list)
    total_rows_scanned: int = 0
    parser_type: str = 'UNKNOWN'

    def __post_init__(self):
        """Validate counts make sense."""
        if self.total_rows_scanned < (len(self.transactions) + len(self.skipped)):
            # Auto-correct if not manually set
            self.total_rows_scanned = len(self.transactions) + len(self.skipped)

    def success_count(self) -> int:
        """Count of successfully parsed transactions."""
        return len(self.transactions)

    def skip_count(self) -> int:
        """Count of skipped transactions."""
        return len(self.skipped)

    def skip_summary(self) -> Dict[str, int]:
        """Aggregate skipped transactions by reason."""
        summary = {}
        for skipped in self.skipped:
            reason = skipped.skip_reason
            summary[reason] = summary.get(reason, 0) + 1
        return summary

    def to_dict(self) -> Dict:
        """Convert to dict for JSON serialization (API-friendly)."""
        return {
            'transactions': [t.to_dict() for t in self.transactions],
            'skipped': [s.to_dict() for s in self.skipped],
            'total_rows_scanned': self.total_rows_scanned,
            'parser_type': self.parser_type,
            'success_count': self.success_count(),
            'skip_count': self.skip_count(),
            'skip_summary': self.skip_summary()
        }


@dataclass
class ParsingSession:
    """
    Represents a complete parsing session for a file.

    Tracks metrics, status, and validation for a single file processing attempt.
    Used by repository layer and for API responses.

    Attributes:
        file_id: Foreign key to processed_files
        parser_type: Parser identifier (e.g., 'HANA', 'TOSS')
        started_at: ISO format datetime
        total_rows_in_file: Total rows scanned by parser
        completed_at: ISO format datetime when completed
        rows_saved: Count of successfully inserted transactions
        rows_skipped: Count of skipped transactions
        rows_duplicate: Count of duplicate transactions
        status: Session status ('pending', 'completed', 'failed')
        error_message: Error message if failed
        validation_status: Validation result ('pass', 'warning', 'fail')
        validation_notes: Human-readable validation summary
        id: Database ID (set after insert)
    """
    file_id: int
    parser_type: str
    started_at: str
    total_rows_in_file: int

    # Set after parsing completes
    completed_at: Optional[str] = None
    rows_saved: int = 0
    rows_skipped: int = 0
    rows_duplicate: int = 0
    status: str = 'pending'
    error_message: Optional[str] = None
    validation_status: Optional[str] = None
    validation_notes: Optional[str] = None

    # Database ID (set after insert)
    id: Optional[int] = None

    def to_dict(self) -> Dict:
        """Convert to dict for JSON serialization (API-friendly)."""
        return {
            'id': self.id,
            'file_id': self.file_id,
            'parser_type': self.parser_type,
            'started_at': self.started_at,
            'completed_at': self.completed_at,
            'total_rows_in_file': self.total_rows_in_file,
            'rows_saved': self.rows_saved,
            'rows_skipped': self.rows_skipped,
            'rows_duplicate': self.rows_duplicate,
            'status': self.status,
            'error_message': self.error_message,
            'validation_status': self.validation_status,
            'validation_notes': self.validation_notes
        }
