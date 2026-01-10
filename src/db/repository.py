"""
Repository pattern implementation for database access layer.
Provides CRUD operations for categories, financial institutions, and transactions.
"""

import sqlite3
import logging
from typing import List, Optional, Dict
from src.models import Transaction


class CategoryRepository:
    """
    Repository for category management with in-memory caching.

    Provides fast lookups and automatic creation of categories.
    Caches all categories on initialization to avoid repeated DB queries.

    Attributes:
        conn: SQLite database connection
        _cache: In-memory dict mapping category names to IDs
        logger: Logger instance for operations tracking

    Examples:
        >>> repo = CategoryRepository(conn)
        >>> category_id = repo.get_or_create('식비')
        >>> print(category_id)
        1
    """

    def __init__(self, connection: sqlite3.Connection):
        """
        Initialize repository with database connection.

        Loads all existing categories into memory cache for fast lookups.

        Args:
            connection: SQLite database connection instance
        """
        self.conn = connection
        self._cache: Dict[str, int] = {}
        self.logger = logging.getLogger(__name__)
        self._load_cache()

    def _load_cache(self):
        """
        Load all categories from database into memory cache.

        Called automatically during initialization. Provides O(1) lookups
        for category IDs without hitting the database.

        Notes:
            - Fetches all categories in single query
            - Builds name -> id mapping dictionary
            - Logged for debugging purposes
        """
        try:
            cursor = self.conn.execute('SELECT id, name FROM categories')
            for row in cursor:
                self._cache[row['name']] = row['id']
            self.logger.debug(f'Loaded {len(self._cache)} categories into cache')
        except Exception as e:
            self.logger.error(f'Failed to load category cache: {e}')
            raise

    def get_or_create(self, name: str) -> int:
        """
        Get category ID by name, creating if it doesn't exist.

        Fast path: Returns cached ID if category exists in cache.
        Slow path: Inserts new category and updates cache.

        Args:
            name: Category name (e.g., '식비', '교통', '통신')

        Returns:
            int: Category ID

        Examples:
            >>> repo = CategoryRepository(conn)
            >>> id1 = repo.get_or_create('식비')
            >>> id2 = repo.get_or_create('식비')  # Cached, no DB query
            >>> assert id1 == id2

        Notes:
            - Uses INSERT OR IGNORE for automatic duplicate handling
            - Updates cache on successful insert
            - Thread-safe with database UNIQUE constraint
        """
        # Fast path: return cached ID
        if name in self._cache:
            return self._cache[name]

        # Slow path: insert and cache
        try:
            cursor = self.conn.execute(
                'INSERT OR IGNORE INTO categories (name) VALUES (?)',
                (name,)
            )
            self.conn.commit()

            # If insert succeeded, use the lastrowid
            if cursor.lastrowid > 0:
                self._cache[name] = cursor.lastrowid
                self.logger.debug(f'Created new category: {name} (id={cursor.lastrowid})')
                return cursor.lastrowid

            # If INSERT OR IGNORE did nothing, fetch existing ID
            cursor = self.conn.execute('SELECT id FROM categories WHERE name = ?', (name,))
            row = cursor.fetchone()
            if row:
                self._cache[name] = row['id']
                return row['id']

            raise ValueError(f'Failed to get or create category: {name}')

        except Exception as e:
            self.logger.error(f'Error in get_or_create for category {name}: {e}')
            raise

    def get_all(self) -> List[dict]:
        """
        Get all categories ordered by name.

        Returns:
            List of category dictionaries with all fields

        Examples:
            >>> repo = CategoryRepository(conn)
            >>> categories = repo.get_all()
            >>> print(categories[0]['name'])
            '식비'
        """
        cursor = self.conn.execute('SELECT * FROM categories ORDER BY name')
        return [dict(row) for row in cursor.fetchall()]

    def get_by_name(self, name: str) -> Optional[dict]:
        """
        Get category by name.

        Args:
            name: Category name

        Returns:
            Category dict or None if not found

        Examples:
            >>> repo = CategoryRepository(conn)
            >>> category = repo.get_by_name('식비')
            >>> print(category['id'])
            1
        """
        cursor = self.conn.execute('SELECT * FROM categories WHERE name = ?', (name,))
        row = cursor.fetchone()
        return dict(row) if row else None


class InstitutionRepository:
    """
    Repository for financial institution management with caching.

    Manages banks, credit cards, and payment services with automatic
    type inference from institution names.

    Attributes:
        conn: SQLite database connection
        _cache: In-memory dict mapping institution names to IDs
        logger: Logger instance for operations tracking

    Examples:
        >>> repo = InstitutionRepository(conn)
        >>> id = repo.get_or_create('하나카드', 'CARD')
        >>> print(id)
        1
    """

    def __init__(self, connection: sqlite3.Connection):
        """
        Initialize repository with database connection.

        Loads all existing institutions into memory cache.

        Args:
            connection: SQLite database connection instance
        """
        self.conn = connection
        self._cache: Dict[str, int] = {}
        self.logger = logging.getLogger(__name__)
        self._load_cache()

    def _load_cache(self):
        """
        Load all financial institutions from database into memory cache.

        Called automatically during initialization for O(1) lookups.
        """
        try:
            cursor = self.conn.execute('SELECT id, name FROM financial_institutions')
            for row in cursor:
                self._cache[row['name']] = row['id']
            self.logger.debug(f'Loaded {len(self._cache)} institutions into cache')
        except Exception as e:
            self.logger.error(f'Failed to load institution cache: {e}')
            raise

    def _infer_type(self, name: str) -> str:
        """
        Infer institution type from name.

        Uses keyword matching to determine if institution is CARD, BANK, or PAY.

        Args:
            name: Institution name (Korean)

        Returns:
            str: Institution type ('CARD', 'BANK', or 'PAY')

        Examples:
            >>> repo._infer_type('하나카드')
            'CARD'
            >>> repo._infer_type('토스뱅크')
            'BANK'
            >>> repo._infer_type('카카오페이')
            'PAY'
        """
        name_lower = name.lower()
        if '카드' in name_lower or 'card' in name_lower:
            return 'CARD'
        elif '뱅크' in name_lower or 'bank' in name_lower or '은행' in name_lower:
            return 'BANK'
        elif '페이' in name_lower or 'pay' in name_lower:
            return 'PAY'
        return 'PAY'  # Default to PAY for unknown types

    def get_or_create(self, name: str, institution_type: Optional[str] = None) -> int:
        """
        Get institution ID by name, creating if it doesn't exist.

        Fast path: Returns cached ID if institution exists.
        Slow path: Inserts new institution with type inference.

        Args:
            name: Institution name (e.g., '하나카드', '토스뱅크')
            institution_type: Optional type override ('CARD', 'BANK', 'PAY')
                            If None, type is inferred from name

        Returns:
            int: Institution ID

        Examples:
            >>> repo = InstitutionRepository(conn)
            >>> id1 = repo.get_or_create('하나카드')  # Type inferred as CARD
            >>> id2 = repo.get_or_create('하나카드', 'CARD')  # Same result
            >>> assert id1 == id2

        Notes:
            - Automatic type inference if institution_type is None
            - Uses INSERT OR IGNORE for duplicate handling
            - Updates cache on successful insert
        """
        # Fast path: return cached ID
        if name in self._cache:
            return self._cache[name]

        # Infer type if not provided
        if institution_type is None:
            institution_type = self._infer_type(name)

        # Slow path: insert and cache
        try:
            cursor = self.conn.execute(
                'INSERT OR IGNORE INTO financial_institutions (name, institution_type, display_name) VALUES (?, ?, ?)',
                (name, institution_type, name)
            )
            self.conn.commit()

            # If insert succeeded, use the lastrowid
            if cursor.lastrowid > 0:
                self._cache[name] = cursor.lastrowid
                self.logger.debug(f'Created new institution: {name} ({institution_type}, id={cursor.lastrowid})')
                return cursor.lastrowid

            # If INSERT OR IGNORE did nothing, fetch existing ID
            cursor = self.conn.execute('SELECT id FROM financial_institutions WHERE name = ?', (name,))
            row = cursor.fetchone()
            if row:
                self._cache[name] = row['id']
                return row['id']

            raise ValueError(f'Failed to get or create institution: {name}')

        except Exception as e:
            self.logger.error(f'Error in get_or_create for institution {name}: {e}')
            raise

    def get_all(self) -> List[dict]:
        """
        Get all active financial institutions ordered by name.

        Returns:
            List of institution dictionaries

        Examples:
            >>> repo = InstitutionRepository(conn)
            >>> institutions = repo.get_all()
            >>> print(institutions[0]['name'])
            '신한카드'
        """
        cursor = self.conn.execute(
            'SELECT * FROM financial_institutions WHERE is_active = 1 ORDER BY name'
        )
        return [dict(row) for row in cursor.fetchall()]

    def get_by_name(self, name: str) -> Optional[dict]:
        """
        Get institution by name.

        Args:
            name: Institution name

        Returns:
            Institution dict or None if not found

        Examples:
            >>> repo = InstitutionRepository(conn)
            >>> inst = repo.get_by_name('하나카드')
            >>> print(inst['institution_type'])
            'CARD'
        """
        cursor = self.conn.execute('SELECT * FROM financial_institutions WHERE name = ?', (name,))
        row = cursor.fetchone()
        return dict(row) if row else None


class TransactionRepository:
    """
    Repository for transaction management with deduplication.

    Handles transaction insertion with automatic date parsing, category/institution
    mapping, and duplicate detection via UNIQUE constraints.

    Attributes:
        conn: SQLite database connection
        category_repo: CategoryRepository for category lookups
        institution_repo: InstitutionRepository for institution lookups
        logger: Logger instance for operations tracking

    Examples:
        >>> category_repo = CategoryRepository(conn)
        >>> institution_repo = InstitutionRepository(conn)
        >>> repo = TransactionRepository(conn, category_repo, institution_repo)
        >>> txn = Transaction(month='09', date='2025.09.13', category='식비',
        ...                   item='스타벅스', amount=5000, source='하나카드')
        >>> txn_id = repo.insert(txn)
        >>> print(txn_id)
        1
    """

    def __init__(self, connection: sqlite3.Connection,
                 category_repo: CategoryRepository,
                 institution_repo: InstitutionRepository):
        """
        Initialize repository with database connection and dependency repos.

        Args:
            connection: SQLite database connection
            category_repo: Repository for category lookups
            institution_repo: Repository for institution lookups
        """
        self.conn = connection
        self.category_repo = category_repo
        self.institution_repo = institution_repo
        self.logger = logging.getLogger(__name__)

    def _parse_date(self, date_str: str) -> tuple:
        """
        Parse transaction date from yyyy.mm.dd to database format.

        Args:
            date_str: Date string in format 'yyyy.mm.dd' (e.g., '2025.09.13')

        Returns:
            Tuple of (db_date: str, year: int, month: int)
            db_date in format 'yyyy-mm-dd' for DATE column
            year and month as integers for indexed columns

        Examples:
            >>> repo._parse_date('2025.09.13')
            ('2025-09-13', 2025, 9)

        Notes:
            - Converts dot separators to hyphens for SQL DATE type
            - Extracts year and month for indexed query optimization
        """
        date_parts = date_str.split('.')
        year = int(date_parts[0])
        month = int(date_parts[1])
        db_date = f'{date_parts[0]}-{date_parts[1]}-{date_parts[2]}'
        return db_date, year, month

    def insert(self, transaction: Transaction, auto_commit: bool = True) -> int:
        """
        Insert a single transaction into database.

        Automatically maps category and institution names to IDs, parses dates,
        and handles duplicates via INSERT OR IGNORE.

        Args:
            transaction: Transaction object with all fields
            auto_commit: If True, commits after insert (default: True)

        Returns:
            int: Transaction ID (lastrowid) or 0 if duplicate was ignored

        Examples:
            >>> txn = Transaction(month='09', date='2025.09.13', category='식비',
            ...                   item='스타벅스', amount=5000, source='하나카드')
            >>> txn_id = repo.insert(txn)
            >>> print(txn_id)
            1

        Notes:
            - Uses get_or_create for categories and institutions
            - INSERT OR IGNORE prevents duplicate constraint violations
            - Returns 0 if transaction already exists (UNIQUE constraint)
            - Handles NULL installment fields gracefully
        """
        try:
            # Parse date to database format
            db_date, year, month = self._parse_date(transaction.date)

            # Map category and institution names to IDs
            category_id = self.category_repo.get_or_create(transaction.category)
            institution_id = self.institution_repo.get_or_create(transaction.source)

            # Insert transaction with deduplication
            cursor = self.conn.execute('''
                INSERT OR IGNORE INTO transactions (
                    transaction_year,
                    transaction_month,
                    transaction_date,
                    category_id,
                    institution_id,
                    merchant_name,
                    amount,
                    installment_months,
                    installment_current,
                    original_amount,
                    raw_description
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                year,
                month,
                db_date,
                category_id,
                institution_id,
                transaction.item,
                transaction.amount,
                transaction.installment_months,
                transaction.installment_current,
                transaction.original_amount,
                f'{transaction.month}/{transaction.date} {transaction.item}'
            ))

            if auto_commit:
                self.conn.commit()

            if cursor.lastrowid > 0:
                self.logger.debug(f'Inserted transaction: {transaction.date} {transaction.item} {transaction.amount}원')
            else:
                self.logger.debug(f'Duplicate transaction ignored: {transaction.date} {transaction.item}')

            return cursor.lastrowid

        except Exception as e:
            self.logger.error(f'Error inserting transaction: {transaction} - {e}')
            raise

    def batch_insert(self, transactions: List[Transaction]) -> int:
        """
        Insert multiple transactions in a single database transaction.

        Wraps all inserts in single commit for performance. Uses explicit
        transaction to avoid N autocommits.

        Args:
            transactions: List of Transaction objects to insert

        Returns:
            int: Number of transactions successfully inserted (duplicates not counted)

        Examples:
            >>> txn1 = Transaction(...)
            >>> txn2 = Transaction(...)
            >>> count = repo.batch_insert([txn1, txn2, txn1])
            >>> print(count)  # 2, duplicate ignored
            2

        Notes:
            - All inserts in single transaction for performance
            - Duplicates silently skipped via INSERT OR IGNORE
            - Rollback on any error (atomic operation)
            - Significantly faster than individual inserts
        """
        if not transactions:
            self.logger.info('No transactions to insert')
            return 0

        count = 0
        try:
            # Batch all inserts without individual commits
            for txn in transactions:
                result = self.insert(txn, auto_commit=False)
                if result > 0:
                    count += 1

            # Single commit for all inserts
            self.conn.commit()
            self.logger.info(f'Batch inserted {count} transactions (out of {len(transactions)} total)')

        except Exception as e:
            self.conn.rollback()
            self.logger.error(f'Batch insert failed, rolled back: {e}')
            raise

        return count

    def get_by_year(self, year: int) -> List[dict]:
        """
        Get all transactions for a specific year.

        Returns transactions ordered by date (most recent first).

        Args:
            year: Year to query (e.g., 2025)

        Returns:
            List of transaction dictionaries with all fields

        Examples:
            >>> repo = TransactionRepository(conn, cat_repo, inst_repo)
            >>> transactions = repo.get_by_year(2025)
            >>> print(len(transactions))
            85
            >>> print(transactions[0]['transaction_date'])
            '2025-09-13'

        Notes:
            - Uses indexed query (transaction_year index)
            - Ordered by date descending for recent-first view
            - Returns dict rows for easy access
        """
        cursor = self.conn.execute('''
            SELECT * FROM transactions
            WHERE transaction_year = ?
            ORDER BY transaction_date DESC
        ''', (year,))
        return [dict(row) for row in cursor.fetchall()]

    def get_monthly_summary(self, year: int, month: int) -> List[dict]:
        """
        Get spending summary by category for a specific month.

        Aggregates total spending per category with category names.

        Args:
            year: Year to query (e.g., 2025)
            month: Month to query (1-12)

        Returns:
            List of dicts with 'category' and 'total' keys, ordered by total descending

        Examples:
            >>> summary = repo.get_monthly_summary(2025, 9)
            >>> print(summary[0])
            {'category': '식비', 'total': 150000}
            >>> print(summary[1])
            {'category': '교통', 'total': 80000}

        Notes:
            - Uses indexed query (transaction_year, transaction_month)
            - Groups by category_id and joins for names
            - Ordered by total spending (highest first)
            - Useful for monthly expense analysis
        """
        cursor = self.conn.execute('''
            SELECT c.name as category, SUM(t.amount) as total
            FROM transactions t
            JOIN categories c ON t.category_id = c.id
            WHERE t.transaction_year = ? AND t.transaction_month = ?
            GROUP BY c.id, c.name
            ORDER BY total DESC
        ''', (year, month))
        return [dict(row) for row in cursor.fetchall()]
