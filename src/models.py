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
