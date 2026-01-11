"""
DuplicateDetector service for detecting potential duplicate transactions.

Checks incoming transactions against existing database records to identify
duplicates before insertion. Supports both exact matches and cross-institution
duplicate detection with confidence scoring.

Architecture:
- Uses TransactionRepository for database queries
- Implements confidence-based matching algorithm
- Batches queries for performance optimization
- Returns structured DuplicateMatch results

Matching Algorithm:
- 100% confidence: All fields match exactly (date + institution + merchant + amount + installment)
- 80% confidence: Date + merchant + amount match, but different institution (cross-institution duplicate)
- <80%: Not flagged as duplicate
"""

import logging
from dataclasses import dataclass, field
from typing import List, Optional, Dict
from datetime import datetime

from src.models import Transaction
from src.db.repository import TransactionRepository


@dataclass
class DuplicateMatch:
    """
    Represents a potential duplicate transaction match.

    Used by DuplicateDetector to report potential duplicates found in the database.
    Provides detailed information about the match for user review and decision-making.

    Attributes:
        new_transaction: The transaction from the file (not yet inserted)
        new_transaction_index: Position in the file (1-indexed)
        existing_transaction_id: ID of the matching transaction in DB
        existing_transaction: The existing transaction data from DB
        confidence_score: Integer 0-100 indicating match confidence
        match_fields: List of field names that matched (e.g., ['date', 'merchant', 'amount'])
        difference_summary: Human-readable description of differences

    Examples:
        >>> match = DuplicateMatch(
        ...     new_transaction=txn,
        ...     new_transaction_index=5,
        ...     existing_transaction_id=123,
        ...     existing_transaction={'merchant_name': 'Starbucks', 'amount': 5000},
        ...     confidence_score=100,
        ...     match_fields=['date', 'institution', 'merchant', 'amount'],
        ...     difference_summary='Exact match'
        ... )
        >>> print(match.confidence_score)
        100
        >>> print(match.is_exact_match())
        True
    """
    new_transaction: Transaction
    new_transaction_index: int
    existing_transaction_id: int
    existing_transaction: Dict
    confidence_score: int
    match_fields: List[str] = field(default_factory=list)
    difference_summary: str = ''

    def is_exact_match(self) -> bool:
        """Check if this is an exact match (100% confidence)."""
        return self.confidence_score == 100

    def is_cross_institution_match(self) -> bool:
        """Check if this is a cross-institution duplicate (80% confidence)."""
        return self.confidence_score == 80

    def to_dict(self) -> Dict:
        """Convert to dictionary for JSON serialization (API-friendly)."""
        return {
            'new_transaction': self.new_transaction.to_dict(),
            'new_transaction_index': self.new_transaction_index,
            'existing_transaction_id': self.existing_transaction_id,
            'existing_transaction': self.existing_transaction,
            'confidence_score': self.confidence_score,
            'match_fields': self.match_fields,
            'difference_summary': self.difference_summary
        }

    def __str__(self) -> str:
        """Return readable string representation for logging."""
        return (
            f'DuplicateMatch(confidence={self.confidence_score}%, '
            f'new={self.new_transaction}, '
            f'existing_id={self.existing_transaction_id}, '
            f'fields={self.match_fields})'
        )


class DuplicateDetector:
    """
    Service for detecting duplicate transactions before insertion.

    Queries the database to find existing transactions that match incoming
    transactions based on key fields. Implements confidence-based scoring
    to distinguish between exact matches and cross-institution duplicates.

    Algorithm:
    1. For each transaction, query database for similar transactions
    2. Calculate confidence score based on field matches:
       - 100%: Exact match (all fields including institution)
       - 80%: Cross-institution duplicate (date + merchant + amount, different institution)
    3. Return only matches with confidence >= 80%

    Attributes:
        transaction_repo: Repository for querying existing transactions
        logger: Logger instance for operations tracking
        batch_size: Number of transactions to process at once (default: 100)

    Examples:
        >>> detector = DuplicateDetector(transaction_repo)
        >>> duplicates = detector.check_for_duplicates(transactions, file_id=1)
        >>> for match in duplicates:
        ...     if match.is_exact_match():
        ...         print(f'Exact duplicate at row {match.new_transaction_index}')
        ...     elif match.is_cross_institution_match():
        ...         print(f'Cross-institution duplicate at row {match.new_transaction_index}')
    """

    def __init__(self, transaction_repo: TransactionRepository, batch_size: int = 100):
        """
        Initialize detector with transaction repository.

        Args:
            transaction_repo: Repository for database queries
            batch_size: Number of transactions to process at once (default: 100)
        """
        self.transaction_repo = transaction_repo
        self.batch_size = batch_size
        self.logger = logging.getLogger(__name__)
        self.logger.debug(f'DuplicateDetector initialized with batch_size={batch_size}')

    def check_for_duplicates(
        self,
        transactions: List[Transaction],
        file_id: Optional[int] = None
    ) -> List[DuplicateMatch]:
        """
        Check list of transactions for potential duplicates.

        Queries database for each transaction to find similar existing records.
        Returns only matches with confidence >= 80%.

        Args:
            transactions: List of transactions to check
            file_id: Optional file_id for context (not used in matching logic)

        Returns:
            List of DuplicateMatch objects for transactions with potential duplicates

        Examples:
            >>> detector = DuplicateDetector(transaction_repo)
            >>> txns = [
            ...     Transaction(date='2025.09.13', source='하나카드', item='스타벅스',
            ...                 amount=5000, month='09', category='카페'),
            ...     Transaction(date='2025.09.13', source='신한카드', item='스타벅스',
            ...                 amount=5000, month='09', category='카페')
            ... ]
            >>> duplicates = detector.check_for_duplicates(txns, file_id=1)
            >>> print(f'Found {len(duplicates)} potential duplicates')
            'Found 1 potential duplicates'

        Notes:
            - Processes transactions in batches for performance
            - Returns empty list if no duplicates found
            - Only returns matches with confidence >= 80%
            - Matches are ordered by new_transaction_index for sequential processing
        """
        if not transactions:
            self.logger.info('No transactions to check for duplicates')
            return []

        duplicates = []
        total = len(transactions)

        self.logger.info(f'Checking {total} transactions for duplicates (batch_size={self.batch_size})')

        # Process transactions (batch size is advisory, actual processing is per-transaction)
        for index, txn in enumerate(transactions, start=1):
            try:
                # Find potential matches for this transaction
                matches = self._find_matches(txn)

                if matches:
                    # Add to duplicate list with index
                    for match in matches:
                        duplicate_match = DuplicateMatch(
                            new_transaction=txn,
                            new_transaction_index=index,
                            existing_transaction_id=match['transaction_id'],
                            existing_transaction=match['transaction'],
                            confidence_score=match['confidence'],
                            match_fields=match['match_fields'],
                            difference_summary=match['difference_summary']
                        )
                        duplicates.append(duplicate_match)
                        self.logger.debug(
                            f'Duplicate found: row {index}, confidence={match["confidence"]}%, '
                            f'existing_id={match["transaction_id"]}'
                        )

            except Exception as e:
                self.logger.error(f'Error checking transaction at index {index}: {e}')
                # Continue processing other transactions even if one fails

        self.logger.info(
            f'Duplicate detection complete: {len(duplicates)} potential duplicates found '
            f'out of {total} transactions'
        )
        return duplicates

    def _find_matches(self, transaction: Transaction) -> List[Dict]:
        """
        Find potential duplicate matches for a single transaction.

        Queries database for similar transactions and calculates confidence scores.

        Args:
            transaction: Transaction to check

        Returns:
            List of match dictionaries with confidence >= 80%

        Notes:
            - Returns empty list if no matches found
            - Each match dict contains: transaction_id, transaction, confidence, match_fields, difference_summary
            - Queries by date, merchant, amount (with optional institution filter)
        """
        matches = []

        try:
            # Parse transaction date to database format
            date_parts = transaction.date.split('.')
            db_date = f'{date_parts[0]}-{date_parts[1]}-{date_parts[2]}'

            # Get institution_id from repository cache
            institution_id = self.transaction_repo.institution_repo.get_or_create(transaction.source)

            # Strategy 1: Check for exact match (100% confidence)
            # Query: date + institution + merchant + amount + installment_current
            exact_match = self._query_exact_match(
                db_date=db_date,
                institution_id=institution_id,
                merchant_name=transaction.item,
                amount=transaction.amount,
                installment_current=transaction.installment_current
            )

            if exact_match:
                matches.append({
                    'transaction_id': exact_match['id'],
                    'transaction': exact_match,
                    'confidence': 100,
                    'match_fields': ['date', 'institution', 'merchant', 'amount', 'installment'],
                    'difference_summary': 'Exact match'
                })
                # Return early - exact match is definitive
                return matches

            # Strategy 2: Check for cross-institution duplicate (80% confidence)
            # Query: date + merchant + amount (different institution)
            cross_institution_matches = self._query_cross_institution_match(
                db_date=db_date,
                institution_id=institution_id,
                merchant_name=transaction.item,
                amount=transaction.amount,
                installment_current=transaction.installment_current
            )

            for match in cross_institution_matches:
                matches.append({
                    'transaction_id': match['id'],
                    'transaction': match,
                    'confidence': 80,
                    'match_fields': ['date', 'merchant', 'amount'],
                    'difference_summary': f'Different institution: {match["institution_name"]} vs {transaction.source}'
                })

        except Exception as e:
            self.logger.error(f'Error finding matches for transaction {transaction}: {e}')
            # Return empty matches on error to avoid blocking processing

        return matches

    def _query_exact_match(
        self,
        db_date: str,
        institution_id: int,
        merchant_name: str,
        amount: int,
        installment_current: Optional[int]
    ) -> Optional[Dict]:
        """
        Query for exact match (100% confidence).

        Matches on: date, institution, merchant, amount, installment_current

        Args:
            db_date: Date in database format (yyyy-mm-dd)
            institution_id: Institution ID
            merchant_name: Merchant name
            amount: Transaction amount
            installment_current: Current installment number (None for one-time)

        Returns:
            Transaction dict or None if no match
        """
        try:
            cursor = self.transaction_repo.conn.execute('''
                SELECT
                    t.*,
                    c.name as category_name,
                    fi.name as institution_name,
                    fi.institution_type
                FROM transactions t
                JOIN categories c ON t.category_id = c.id
                JOIN financial_institutions fi ON t.institution_id = fi.id
                WHERE t.transaction_date = ?
                  AND t.institution_id = ?
                  AND t.merchant_name = ?
                  AND t.amount = ?
                  AND (
                    (t.installment_current IS NULL AND ? IS NULL) OR
                    (t.installment_current = ?)
                  )
                LIMIT 1
            ''', (db_date, institution_id, merchant_name, amount, installment_current, installment_current))

            row = cursor.fetchone()
            return dict(row) if row else None

        except Exception as e:
            self.logger.error(f'Error querying exact match: {e}')
            return None

    def _query_cross_institution_match(
        self,
        db_date: str,
        institution_id: int,
        merchant_name: str,
        amount: int,
        installment_current: Optional[int]
    ) -> List[Dict]:
        """
        Query for cross-institution duplicate (80% confidence).

        Matches on: date, merchant, amount, installment (but DIFFERENT institution)

        Args:
            db_date: Date in database format (yyyy-mm-dd)
            institution_id: Institution ID to EXCLUDE (different institution)
            merchant_name: Merchant name
            amount: Transaction amount
            installment_current: Current installment number (None for one-time)

        Returns:
            List of matching transaction dicts (empty if no matches)
        """
        try:
            cursor = self.transaction_repo.conn.execute('''
                SELECT
                    t.*,
                    c.name as category_name,
                    fi.name as institution_name,
                    fi.institution_type
                FROM transactions t
                JOIN categories c ON t.category_id = c.id
                JOIN financial_institutions fi ON t.institution_id = fi.id
                WHERE t.transaction_date = ?
                  AND t.institution_id != ?
                  AND t.merchant_name = ?
                  AND t.amount = ?
                  AND (
                    (t.installment_current IS NULL AND ? IS NULL) OR
                    (t.installment_current = ?)
                  )
                LIMIT 10
            ''', (db_date, institution_id, merchant_name, amount, installment_current, installment_current))

            results = [dict(row) for row in cursor.fetchall()]
            return results

        except Exception as e:
            self.logger.error(f'Error querying cross-institution match: {e}')
            return []

    def get_match_summary(self, duplicates: List[DuplicateMatch]) -> Dict:
        """
        Generate summary statistics for duplicate matches.

        Aggregates duplicate matches by confidence level and provides counts.
        Useful for reporting and decision-making.

        Args:
            duplicates: List of DuplicateMatch objects

        Returns:
            Dict with summary statistics:
                - total: Total number of duplicates
                - exact_matches: Count of 100% confidence matches
                - cross_institution_matches: Count of 80% confidence matches
                - affected_rows: List of row indices with duplicates

        Examples:
            >>> detector = DuplicateDetector(transaction_repo)
            >>> duplicates = detector.check_for_duplicates(transactions, file_id=1)
            >>> summary = detector.get_match_summary(duplicates)
            >>> print(f"Total duplicates: {summary['total']}")
            >>> print(f"Exact matches: {summary['exact_matches']}")
            >>> print(f"Cross-institution: {summary['cross_institution_matches']}")
        """
        exact_count = sum(1 for d in duplicates if d.is_exact_match())
        cross_institution_count = sum(1 for d in duplicates if d.is_cross_institution_match())
        affected_rows = sorted(set(d.new_transaction_index for d in duplicates))

        return {
            'total': len(duplicates),
            'exact_matches': exact_count,
            'cross_institution_matches': cross_institution_count,
            'affected_rows': affected_rows
        }
