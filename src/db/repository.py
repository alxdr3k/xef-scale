"""
Repository pattern implementation for database access layer.
Provides CRUD operations for categories, financial institutions, and transactions.
"""

import sqlite3
import logging
import json
from datetime import datetime
from typing import List, Optional, Dict
from src.models import Transaction, SkippedTransaction


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

    def get_by_id(self, category_id: int) -> Optional[dict]:
        """
        Get category by ID.

        Args:
            category_id: Category ID

        Returns:
            Category dict or None if not found

        Examples:
            >>> repo = CategoryRepository(conn)
            >>> category = repo.get_by_id(1)
            >>> print(category['name'])
            '식비'
        """
        cursor = self.conn.execute('SELECT * FROM categories WHERE id = ?', (category_id,))
        row = cursor.fetchone()
        return dict(row) if row else None

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

    def insert(self, transaction: Transaction, auto_commit: bool = True,
               file_id: Optional[int] = None, row_number: Optional[int] = None) -> int:
        """
        Insert a single transaction into database.

        Automatically maps category and institution names to IDs, parses dates,
        and handles duplicates via INSERT OR IGNORE.

        Args:
            transaction: Transaction object with all fields
            auto_commit: If True, commits after insert (default: True)
            file_id: Optional file_id for file tracking (default: None for backward compatibility)
            row_number: Optional row number within file (default: None for backward compatibility)

        Returns:
            int: Transaction ID (lastrowid) or 0 if duplicate was ignored

        Examples:
            >>> txn = Transaction(month='09', date='2025.09.13', category='식비',
            ...                   item='스타벅스', amount=5000, source='하나카드')
            >>> # Without file tracking (backward compatible)
            >>> txn_id = repo.insert(txn)
            >>> print(txn_id)
            1
            >>> # With file tracking (new behavior)
            >>> txn_id = repo.insert(txn, file_id=5, row_number=3)
            >>> print(txn_id)
            2

        Notes:
            - Uses get_or_create for categories and institutions
            - INSERT OR IGNORE prevents duplicate constraint violations
            - Returns 0 if transaction already exists (UNIQUE constraint)
            - Handles NULL installment fields gracefully
            - file_id and row_number are optional for backward compatibility
            - When provided, enables file-level duplicate detection
        """
        try:
            # Parse date to database format
            db_date, year, month = self._parse_date(transaction.date)

            # Map category and institution names to IDs
            category_id = self.category_repo.get_or_create(transaction.category)
            institution_id = self.institution_repo.get_or_create(transaction.source)

            # Insert transaction with deduplication (including file tracking columns)
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
                    raw_description,
                    file_id,
                    row_number_in_file
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                f'{transaction.month}/{transaction.date} {transaction.item}',
                file_id,
                row_number
            ))

            if auto_commit:
                self.conn.commit()

            # Check rowcount to detect duplicates (INSERT OR IGNORE returns rowcount=0 for duplicates)
            if cursor.rowcount > 0:
                self.logger.debug(f'Inserted transaction: {transaction.date} {transaction.item} {transaction.amount}원')
                return cursor.lastrowid
            else:
                self.logger.debug(f'Duplicate transaction ignored: {transaction.date} {transaction.item}')
                return 0  # Return 0 to indicate duplicate was ignored

        except Exception as e:
            self.logger.error(f'Error inserting transaction: {transaction} - {e}')
            raise

    def batch_insert(self, transactions: List[Transaction], file_id: Optional[int] = None) -> int:
        """
        Insert multiple transactions in a single database transaction.

        Wraps all inserts in single commit for performance. Uses explicit
        transaction to avoid N autocommits.

        Args:
            transactions: List of Transaction objects to insert
            file_id: Optional file_id for file tracking. If provided, auto-assigns
                    row numbers (1-indexed) to each transaction in order

        Returns:
            int: Number of transactions successfully inserted (duplicates not counted)

        Examples:
            >>> txn1 = Transaction(...)
            >>> txn2 = Transaction(...)
            >>> # Without file tracking (backward compatible)
            >>> count = repo.batch_insert([txn1, txn2, txn1])
            >>> print(count)  # 2, duplicate ignored
            2
            >>> # With file tracking (new behavior)
            >>> count = repo.batch_insert([txn1, txn2], file_id=5)
            >>> print(count)  # txn1 gets row_number=1, txn2 gets row_number=2
            2

        Notes:
            - All inserts in single transaction for performance
            - Duplicates silently skipped via INSERT OR IGNORE
            - Rollback on any error (atomic operation)
            - Significantly faster than individual inserts
            - When file_id provided, automatically assigns sequential row numbers
        """
        if not transactions:
            self.logger.info('No transactions to insert')
            return 0

        count = 0
        try:
            # Batch all inserts without individual commits
            for index, txn in enumerate(transactions):
                # If file_id provided, assign row number (1-indexed)
                row_number = (index + 1) if file_id is not None else None
                result = self.insert(txn, auto_commit=False, file_id=file_id, row_number=row_number)
                if result > 0:
                    count += 1

            # Single commit for all inserts
            self.conn.commit()

            if file_id is not None:
                self.logger.info(
                    f'Batch inserted {count} transactions with file_id={file_id} '
                    f'(out of {len(transactions)} total)'
                )
            else:
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

    def get_by_id(self, transaction_id: int) -> Optional[dict]:
        """
        Get single transaction by ID with category and institution names.

        Joins with categories and financial_institutions tables to provide
        complete transaction details including readable names.

        Args:
            transaction_id: Transaction ID to retrieve

        Returns:
            Transaction dict with all fields or None if not found

        Examples:
            >>> repo = TransactionRepository(conn, cat_repo, inst_repo)
            >>> txn = repo.get_by_id(123)
            >>> if txn:
            ...     print(f"{txn['merchant_name']}: {txn['amount']}원")
            ...     print(f"Category: {txn['category_name']}")
            ...     print(f"Institution: {txn['institution_name']}")

        Notes:
            - Joins with categories and financial_institutions for names
            - Returns None if transaction doesn't exist
            - Includes all transaction fields plus joined name columns
        """
        try:
            cursor = self.conn.execute('''
                SELECT
                    t.*,
                    c.name as category_name,
                    fi.name as institution_name,
                    fi.institution_type
                FROM transactions t
                JOIN categories c ON t.category_id = c.id
                JOIN financial_institutions fi ON t.institution_id = fi.id
                WHERE t.id = ? AND t.deleted_at IS NULL
            ''', (transaction_id,))

            row = cursor.fetchone()
            return dict(row) if row else None

        except Exception as e:
            self.logger.error(f'Error fetching transaction by ID {transaction_id}: {e}')
            raise

    def get_filtered(self, year: Optional[int] = None, month: Optional[int] = None,
                     category_id: Optional[int] = None, institution_id: Optional[int] = None,
                     search: Optional[str] = None, sort: str = 'date_desc',
                     limit: int = 50, offset: int = 0) -> tuple[List[dict], int]:
        """
        Get filtered and paginated transactions with total count.

        Supports multiple filters, sorting, and pagination. Returns both
        the matching transactions and total count for pagination metadata.

        Args:
            year: Optional year filter
            month: Optional month filter (1-12)
            category_id: Optional category ID filter
            institution_id: Optional institution ID filter
            search: Optional merchant name search (case-insensitive, partial match)
            sort: Sort order - 'date_desc', 'date_asc', 'amount_desc', 'amount_asc'
            limit: Maximum number of results (default: 50)
            offset: Number of results to skip (default: 0)

        Returns:
            Tuple of (transactions: List[dict], total_count: int)

        Examples:
            >>> repo = TransactionRepository(conn, cat_repo, inst_repo)
            >>> # Get September 2025 food expenses
            >>> txns, total = repo.get_filtered(year=2025, month=9, category_id=1)
            >>> print(f"Found {total} transactions, showing first {len(txns)}")
            >>> # Search for Starbucks transactions
            >>> txns, total = repo.get_filtered(search='스타벅스', limit=10)
            >>> # Get page 2 of all transactions
            >>> txns, total = repo.get_filtered(limit=50, offset=50)

        Notes:
            - All filters are optional and can be combined
            - Uses indexed queries for performance
            - Search is case-insensitive and matches partial merchant names
            - Total count reflects filtered results (not offset/limit)
            - Returns transactions with joined category and institution names
        """
        try:
            # Build WHERE clause dynamically
            where_clauses = ['t.deleted_at IS NULL']  # Always exclude soft-deleted records
            params = []

            if year is not None:
                where_clauses.append('t.transaction_year = ?')
                params.append(year)

            if month is not None:
                where_clauses.append('t.transaction_month = ?')
                params.append(month)

            if category_id is not None:
                where_clauses.append('t.category_id = ?')
                params.append(category_id)

            if institution_id is not None:
                where_clauses.append('t.institution_id = ?')
                params.append(institution_id)

            if search is not None:
                where_clauses.append('t.merchant_name LIKE ?')
                params.append(f'%{search}%')

            where_sql = 'WHERE ' + ' AND '.join(where_clauses)

            # Build ORDER BY clause
            sort_map = {
                'date_desc': 't.transaction_date DESC',
                'date_asc': 't.transaction_date ASC',
                'amount_desc': 't.amount DESC',
                'amount_asc': 't.amount ASC'
            }
            order_sql = f'ORDER BY {sort_map.get(sort, sort_map["date_desc"])}'

            # Get total count (without pagination)
            count_query = f'''
                SELECT COUNT(*) as count
                FROM transactions t
                {where_sql}
            '''
            cursor = self.conn.execute(count_query, params)
            total_count = cursor.fetchone()['count']

            # Get paginated results with joins
            query = f'''
                SELECT
                    t.*,
                    c.name as category_name,
                    fi.name as institution_name,
                    fi.institution_type
                FROM transactions t
                JOIN categories c ON t.category_id = c.id
                JOIN financial_institutions fi ON t.institution_id = fi.id
                {where_sql}
                {order_sql}
                LIMIT ? OFFSET ?
            '''
            cursor = self.conn.execute(query, params + [limit, offset])
            transactions = [dict(row) for row in cursor.fetchall()]

            self.logger.debug(
                f'Filtered transactions: filters={where_clauses}, '
                f'total={total_count}, returned={len(transactions)}'
            )

            return transactions, total_count

        except Exception as e:
            self.logger.error(f'Error in get_filtered: {e}')
            raise

    def get_monthly_summary_with_stats(self, year: int, month: int) -> dict:
        """
        Get comprehensive monthly spending summary with statistics.

        Provides detailed monthly analysis including category breakdown,
        total spending, and transaction count.

        Args:
            year: Year to query (e.g., 2025)
            month: Month to query (1-12)

        Returns:
            Dict with:
                - total_amount: Total spending for the month
                - transaction_count: Total number of transactions
                - by_category: List of category summaries with name, amount, count

        Examples:
            >>> repo = TransactionRepository(conn, cat_repo, inst_repo)
            >>> summary = repo.get_monthly_summary_with_stats(2025, 9)
            >>> print(f"Total: {summary['total_amount']}원")
            >>> print(f"Transactions: {summary['transaction_count']}")
            >>> for cat in summary['by_category']:
            ...     print(f"{cat['category_name']}: {cat['amount']}원 ({cat['count']} txns)")

        Notes:
            - Uses indexed query (transaction_year, transaction_month)
            - Groups by category with counts and sums
            - Ordered by spending amount (highest first)
            - Useful for monthly reports and dashboards
        """
        try:
            # Get category breakdown
            cursor = self.conn.execute('''
                SELECT
                    c.id as category_id,
                    c.name as category_name,
                    SUM(t.amount) as amount,
                    COUNT(*) as count
                FROM transactions t
                JOIN categories c ON t.category_id = c.id
                WHERE t.transaction_year = ? AND t.transaction_month = ?
                GROUP BY c.id, c.name
                ORDER BY amount DESC
            ''', (year, month))

            by_category = [dict(row) for row in cursor.fetchall()]

            # Calculate totals
            total_amount = sum(cat['amount'] for cat in by_category)
            transaction_count = sum(cat['count'] for cat in by_category)

            return {
                'year': year,
                'month': month,
                'total_amount': total_amount,
                'transaction_count': transaction_count,
                'by_category': by_category
            }

        except Exception as e:
            self.logger.error(f'Error in get_monthly_summary_with_stats: {e}')
            raise

    def is_editable(self, transaction_id: int) -> bool:
        """
        Check if a transaction is editable (manual, not parsed from file).

        Only manual transactions (file_id IS NULL) that are active (deleted_at IS NULL)
        can be edited or deleted. Transactions parsed from files are immutable.

        Args:
            transaction_id: Transaction ID to check

        Returns:
            bool: True if editable, False otherwise

        Examples:
            >>> repo = TransactionRepository(conn, cat_repo, inst_repo)
            >>> # Check manual transaction
            >>> if repo.is_editable(123):
            ...     repo.update(123, {'amount': 10000})
            >>> # Check parsed transaction
            >>> if not repo.is_editable(456):
            ...     print("Cannot edit parsed transactions")

        Notes:
            - Returns False if transaction doesn't exist
            - Returns False if transaction has file_id (parsed from file)
            - Returns False if transaction is soft-deleted
            - Use before update() or soft_delete() operations
        """
        try:
            cursor = self.conn.execute('''
                SELECT file_id, deleted_at
                FROM transactions
                WHERE id = ?
            ''', (transaction_id,))

            row = cursor.fetchone()
            if not row:
                self.logger.debug(f'Transaction {transaction_id} not found')
                return False

            # Editable if file_id is NULL and not deleted
            is_manual = row['file_id'] is None
            is_active = row['deleted_at'] is None

            self.logger.debug(
                f'Transaction {transaction_id} editable check: '
                f'manual={is_manual}, active={is_active}'
            )

            return is_manual and is_active

        except Exception as e:
            self.logger.error(f'Error checking editability for transaction {transaction_id}: {e}')
            raise

    def update(self, transaction_id: int, updates: dict, validate_editable: bool = True) -> bool:
        """
        Update manual transaction fields by ID.

        Only manual transactions (file_id IS NULL) can be updated. Protected fields
        (id, file_id, row_number_in_file, created_at, updated_at) cannot be modified.

        Args:
            transaction_id: Transaction ID to update
            updates: Dict of field names to new values
            validate_editable: If True, checks transaction is editable first (default: True)

        Returns:
            bool: True if update successful, False if transaction not found

        Raises:
            ValueError: If transaction is not editable or updates contain protected fields

        Examples:
            >>> repo = TransactionRepository(conn, cat_repo, inst_repo)
            >>> # Update amount
            >>> repo.update(123, {'amount': 10000})
            True
            >>> # Update multiple fields
            >>> repo.update(123, {
            ...     'merchant_name': '스타벅스 강남점',
            ...     'amount': 5500,
            ...     'category': '식비'
            ... })
            True
            >>> # Update with date (auto-extracts year/month)
            >>> repo.update(123, {'transaction_date': '2025.09.15'})
            True
            >>> # Attempt to update parsed transaction
            >>> repo.update(456, {'amount': 10000})
            ValueError: Transaction 456 is not editable (parsed from file or deleted)

        Notes:
            - Protected fields: id, file_id, row_number_in_file, created_at, updated_at
            - Date parsing: If transaction_date provided, auto-extracts year/month
            - Category/institution: Converts names to IDs using get_or_create
            - Only updates active (deleted_at IS NULL) transactions
            - Automatically updates updated_at timestamp
        """
        try:
            # Validate editability first if requested
            if validate_editable and not self.is_editable(transaction_id):
                raise ValueError(
                    f'Transaction {transaction_id} is not editable '
                    '(parsed from file or deleted)'
                )

            # Define protected fields that cannot be updated
            protected_fields = {
                'id', 'file_id', 'row_number_in_file', 'created_at', 'updated_at'
            }

            # Check for protected fields in updates
            protected_in_updates = protected_fields.intersection(updates.keys())
            if protected_in_updates:
                raise ValueError(
                    f'Cannot update protected fields: {protected_in_updates}'
                )

            if not updates:
                self.logger.debug(f'No updates provided for transaction {transaction_id}')
                return False

            # Build SET clause dynamically
            set_clauses = []
            params = []

            # Handle date parsing if transaction_date is provided
            if 'transaction_date' in updates:
                date_str = updates.pop('transaction_date')
                db_date, year, month = self._parse_date(date_str)
                updates['transaction_date'] = db_date
                updates['transaction_year'] = year
                updates['transaction_month'] = month

            # Handle category name to ID conversion
            if 'category' in updates:
                category_name = updates.pop('category')
                category_id = self.category_repo.get_or_create(category_name)
                updates['category_id'] = category_id

            # Handle institution name to ID conversion
            if 'source' in updates or 'institution' in updates:
                institution_name = updates.pop('source', None) or updates.pop('institution', None)
                institution_id = self.institution_repo.get_or_create(institution_name)
                updates['institution_id'] = institution_id

            # Build SET clause for remaining fields
            for field, value in updates.items():
                set_clauses.append(f'{field} = ?')
                params.append(value)

            if not set_clauses:
                self.logger.debug(f'No valid updates after processing for transaction {transaction_id}')
                return False

            # Add updated_at timestamp
            set_clauses.append('updated_at = CURRENT_TIMESTAMP')

            # Build and execute UPDATE query
            set_sql = ', '.join(set_clauses)
            query = f'''
                UPDATE transactions
                SET {set_sql}
                WHERE id = ? AND deleted_at IS NULL
            '''
            params.append(transaction_id)

            cursor = self.conn.execute(query, params)
            self.conn.commit()

            if cursor.rowcount > 0:
                self.logger.info(
                    f'Updated transaction {transaction_id}: {list(updates.keys())}'
                )
                return True
            else:
                self.logger.debug(
                    f'Transaction {transaction_id} not found or already deleted'
                )
                return False

        except Exception as e:
            self.logger.error(f'Error updating transaction {transaction_id}: {e}')
            raise

    def update_notes(self, transaction_id: int, notes: Optional[str]) -> bool:
        """
        Update notes for any transaction (including parsed transactions).

        Unlike other transaction fields, notes can be updated for BOTH manual and
        file-based transactions. This allows users to add context to any transaction
        regardless of its source.

        Args:
            transaction_id: Transaction ID to update
            notes: New notes text or None to clear notes

        Returns:
            bool: True if update successful, False if transaction not found

        Examples:
            >>> repo = TransactionRepository(conn, cat_repo, inst_repo)
            >>> # Add notes to any transaction
            >>> repo.update_notes(123, "회의 중 커피 구매")
            True
            >>> # Clear notes
            >>> repo.update_notes(123, None)
            True
            >>> # Update notes for parsed transaction (allowed)
            >>> repo.update_notes(456, "자동 파싱된 거래에 메모 추가")
            True

        Notes:
            - Works for BOTH manual and parsed transactions (no file_id check)
            - No editability validation required
            - Only updates active (deleted_at IS NULL) transactions
            - Automatically updates updated_at timestamp
        """
        try:
            query = '''
                UPDATE transactions
                SET notes = ?, updated_at = CURRENT_TIMESTAMP
                WHERE id = ? AND deleted_at IS NULL
            '''

            cursor = self.conn.execute(query, (notes, transaction_id))
            self.conn.commit()

            if cursor.rowcount > 0:
                self.logger.info(
                    f'Updated notes for transaction {transaction_id}'
                )
                return True
            else:
                self.logger.debug(
                    f'Transaction {transaction_id} not found or already deleted'
                )
                return False

        except Exception as e:
            self.logger.error(f'Error updating notes for transaction {transaction_id}: {e}')
            raise

    def soft_delete(self, transaction_id: int, validate_editable: bool = True) -> bool:
        """
        Soft delete a manual transaction by setting deleted_at timestamp.

        Only manual transactions (file_id IS NULL) can be deleted. Parsed transactions
        from files are immutable. Soft deletion preserves data for audit trails.

        Args:
            transaction_id: Transaction ID to soft delete
            validate_editable: If True, checks transaction is editable first (default: True)

        Returns:
            bool: True if deletion successful, False if transaction not found

        Raises:
            ValueError: If transaction is not editable (parsed from file)

        Examples:
            >>> repo = TransactionRepository(conn, cat_repo, inst_repo)
            >>> # Delete manual transaction
            >>> repo.soft_delete(123)
            True
            >>> # Verify deletion (should not be found)
            >>> txn = repo.get_by_id(123)
            >>> print(txn)
            None
            >>> # Attempt to delete parsed transaction
            >>> repo.soft_delete(456)
            ValueError: Transaction 456 is not editable (parsed from file or deleted)

        Notes:
            - Only deletes manual transactions (file_id IS NULL)
            - Sets deleted_at = CURRENT_TIMESTAMP
            - Soft-deleted transactions excluded from get_by_id() and get_filtered()
            - Can be recovered by setting deleted_at = NULL (database-level operation)
            - Idempotent: deleting already-deleted transaction returns False
        """
        try:
            # Validate editability first if requested
            if validate_editable and not self.is_editable(transaction_id):
                raise ValueError(
                    f'Transaction {transaction_id} is not editable '
                    '(parsed from file or deleted)'
                )

            # Soft delete by setting deleted_at timestamp
            cursor = self.conn.execute('''
                UPDATE transactions
                SET deleted_at = CURRENT_TIMESTAMP
                WHERE id = ? AND deleted_at IS NULL
            ''', (transaction_id,))

            self.conn.commit()

            if cursor.rowcount > 0:
                self.logger.info(f'Soft deleted transaction {transaction_id}')
                return True
            else:
                self.logger.debug(
                    f'Transaction {transaction_id} not found or already deleted'
                )
                return False

        except Exception as e:
            self.logger.error(f'Error soft deleting transaction {transaction_id}: {e}')
            raise


class ParsingSessionRepository:
    """
    Repository for parsing session tracking and validation.

    Manages parsing session lifecycle including creation, completion, failure tracking,
    and retrieval with statistics. Each session represents one file parsing attempt.

    Attributes:
        conn: SQLite database connection
        logger: Logger instance for operations tracking

    Examples:
        >>> repo = ParsingSessionRepository(conn)
        >>> session_id = repo.create_session(file_id=1, parser_type='HANA', total_rows=100)
        >>> repo.complete_session(session_id, rows_saved=85, rows_skipped=5,
        ...                       rows_duplicate=10, validation_status='pass',
        ...                       validation_notes='All validations passed')
        >>> sessions = repo.get_recent_sessions(limit=10)
        >>> print(sessions[0]['parser_type'])
        'HANA'
    """

    def __init__(self, connection: sqlite3.Connection):
        """
        Initialize repository with database connection.

        Args:
            connection: SQLite database connection instance
        """
        self.conn = connection
        self.logger = logging.getLogger(__name__)
        self.logger.debug('ParsingSessionRepository initialized')

    def create_session(self, file_id: int, parser_type: str, total_rows: int) -> int:
        """
        Create a new parsing session with pending status.

        Initializes session tracking for a file parsing operation.
        Sets status to 'pending' and records start time.

        Args:
            file_id: Foreign key to processed_files table
            parser_type: Parser identifier (e.g., 'HANA', 'TOSS', 'SHINHAN')
            total_rows: Total rows scanned in file

        Returns:
            int: Session ID (lastrowid)

        Examples:
            >>> repo = ParsingSessionRepository(conn)
            >>> session_id = repo.create_session(file_id=1, parser_type='HANA', total_rows=100)
            >>> print(session_id)
            1

        Notes:
            - Status automatically set to 'pending'
            - started_at automatically set to current timestamp
            - Session must be completed via complete_session() or fail_session()
        """
        try:
            started_at = datetime.now().isoformat()
            cursor = self.conn.execute('''
                INSERT INTO parsing_sessions (
                    file_id,
                    parser_type,
                    started_at,
                    total_rows_in_file,
                    status
                ) VALUES (?, ?, ?, ?, 'pending')
            ''', (file_id, parser_type, started_at, total_rows))

            self.conn.commit()

            self.logger.debug(
                f'Created parsing session: file_id={file_id}, parser={parser_type}, '
                f'total_rows={total_rows}, session_id={cursor.lastrowid}'
            )
            return cursor.lastrowid

        except Exception as e:
            self.logger.error(f'Error creating parsing session for file_id={file_id}: {e}')
            raise

    def complete_session(self, session_id: int, rows_saved: int, rows_skipped: int,
                        rows_duplicate: int, validation_status: str,
                        validation_notes: str):
        """
        Mark session as completed with final statistics.

        Updates session with completion timestamp, row counts, validation results,
        and sets status to 'completed'.

        Args:
            session_id: Session ID from create_session()
            rows_saved: Count of successfully inserted transactions
            rows_skipped: Count of skipped transactions
            rows_duplicate: Count of duplicate transactions (INSERT OR IGNORE)
            validation_status: Validation result ('pass', 'warning', 'fail')
            validation_notes: Human-readable validation summary

        Examples:
            >>> repo = ParsingSessionRepository(conn)
            >>> repo.complete_session(
            ...     session_id=1,
            ...     rows_saved=85,
            ...     rows_skipped=5,
            ...     rows_duplicate=10,
            ...     validation_status='pass',
            ...     validation_notes='All validations passed. No critical issues.'
            ... )

        Notes:
            - Sets completed_at to current timestamp
            - Sets status to 'completed'
            - Commits immediately
            - Should be called after successful parsing and insertion
        """
        try:
            completed_at = datetime.now().isoformat()
            self.conn.execute('''
                UPDATE parsing_sessions
                SET completed_at = ?,
                    rows_saved = ?,
                    rows_skipped = ?,
                    rows_duplicate = ?,
                    status = 'completed',
                    validation_status = ?,
                    validation_notes = ?
                WHERE id = ?
            ''', (completed_at, rows_saved, rows_skipped, rows_duplicate,
                  validation_status, validation_notes, session_id))

            self.conn.commit()

            self.logger.info(
                f'Completed parsing session {session_id}: saved={rows_saved}, '
                f'skipped={rows_skipped}, duplicate={rows_duplicate}, validation={validation_status}'
            )

        except Exception as e:
            self.logger.error(f'Error completing parsing session {session_id}: {e}')
            raise

    def fail_session(self, session_id: int, error_message: str):
        """
        Mark session as failed with error message.

        Updates session with completion timestamp, error message,
        and sets status to 'failed'.

        Args:
            session_id: Session ID from create_session()
            error_message: Error message describing the failure

        Examples:
            >>> repo = ParsingSessionRepository(conn)
            >>> repo.fail_session(session_id=1, error_message='Invalid file format')

        Notes:
            - Sets completed_at to current timestamp
            - Sets status to 'failed'
            - Commits immediately
            - Should be called when parsing or insertion fails
        """
        try:
            completed_at = datetime.now().isoformat()
            self.conn.execute('''
                UPDATE parsing_sessions
                SET completed_at = ?,
                    status = 'failed',
                    error_message = ?
                WHERE id = ?
            ''', (completed_at, error_message, session_id))

            self.conn.commit()

            self.logger.error(f'Failed parsing session {session_id}: {error_message}')

        except Exception as e:
            self.logger.error(f'Error marking session {session_id} as failed: {e}')
            raise

    def update_status(self, session_id: int, status: str):
        """
        Update parsing session status.

        Used to mark sessions as 'pending_confirmation' when duplicate transactions
        are detected and require user review before insertion.

        Args:
            session_id: Session ID from create_session()
            status: New status ('pending_confirmation', 'completed', 'failed', 'pending')

        Examples:
            >>> repo = ParsingSessionRepository(conn)
            >>> repo.update_status(session_id=1, status='pending_confirmation')

        Notes:
            - Does not update completed_at timestamp (session still in progress)
            - Commits immediately
            - Used primarily for duplicate detection workflow
            - Status values: 'pending', 'pending_confirmation', 'completed', 'failed'
        """
        try:
            self.conn.execute('''
                UPDATE parsing_sessions
                SET status = ?
                WHERE id = ?
            ''', (status, session_id))

            self.conn.commit()

            self.logger.info(f'Updated parsing session {session_id} status to: {status}')

        except Exception as e:
            self.logger.error(f'Error updating session {session_id} status: {e}')
            raise

    def update_processing_result(self, session_id: int, rows_saved: int, rows_pending: int):
        """
        Update parsing session with partial processing results.

        Used when some transactions are inserted but others are pending user
        confirmation for duplicate resolution. Updates row counts without
        marking session as completed.

        Args:
            session_id: Session ID from create_session()
            rows_saved: Count of successfully inserted transactions (non-duplicates)
            rows_pending: Count of transactions pending user confirmation (duplicates)

        Examples:
            >>> repo = ParsingSessionRepository(conn)
            >>> repo.update_processing_result(session_id=1, rows_saved=82, rows_pending=3)

        Notes:
            - Does not set completed_at (session remains open for confirmation)
            - Does not change status (use update_status() for that)
            - Commits immediately
            - Used in conjunction with update_status() for duplicate workflow
            - rows_pending represents count of duplicate confirmations awaiting review
        """
        try:
            self.conn.execute('''
                UPDATE parsing_sessions
                SET rows_saved = ?,
                    rows_duplicate = ?
                WHERE id = ?
            ''', (rows_saved, rows_pending, session_id))

            self.conn.commit()

            self.logger.info(
                f'Updated parsing session {session_id}: saved={rows_saved}, pending={rows_pending}'
            )

        except Exception as e:
            self.logger.error(f'Error updating processing result for session {session_id}: {e}')
            raise

    def get_recent_sessions(self, limit: int = 50, offset: int = 0) -> List[dict]:
        """
        Get recent parsing sessions with file and institution details.

        Joins with processed_files and financial_institutions for complete context.
        Ordered by session start time (most recent first).

        Args:
            limit: Maximum number of sessions to return (default: 50)
            offset: Number of sessions to skip for pagination (default: 0)

        Returns:
            List of session dictionaries with joined file and institution data

        Examples:
            >>> repo = ParsingSessionRepository(conn)
            >>> sessions = repo.get_recent_sessions(limit=10)
            >>> for session in sessions:
            ...     print(f"{session['file_name']} - {session['institution_name']}")
            'hana_statement.xls - 하나카드'
            'toss_statement.csv - 토스뱅크'

        Notes:
            - Joins with processed_files for file_name, file_hash
            - Joins with financial_institutions for institution_name
            - Ordered by started_at DESC (most recent first)
            - Supports pagination via limit/offset
        """
        try:
            cursor = self.conn.execute('''
                SELECT
                    ps.*,
                    pf.file_name,
                    pf.file_hash,
                    fi.name as institution_name,
                    fi.institution_type
                FROM parsing_sessions ps
                JOIN processed_files pf ON ps.file_id = pf.id
                JOIN financial_institutions fi ON pf.institution_id = fi.id
                ORDER BY ps.started_at DESC
                LIMIT ? OFFSET ?
            ''', (limit, offset))

            results = [dict(row) for row in cursor.fetchall()]
            self.logger.debug(f'Retrieved {len(results)} recent sessions (limit={limit}, offset={offset})')
            return results

        except Exception as e:
            self.logger.error(f'Error fetching recent sessions: {e}')
            raise

    def get_with_stats(self, session_id: int) -> Optional[dict]:
        """
        Get single parsing session with file and institution details.

        Same join as get_recent_sessions() but for single session lookup.

        Args:
            session_id: Session ID to retrieve

        Returns:
            Session dict with joined data or None if not found

        Examples:
            >>> repo = ParsingSessionRepository(conn)
            >>> session = repo.get_with_stats(session_id=1)
            >>> if session:
            ...     print(f"Parser: {session['parser_type']}")
            ...     print(f"File: {session['file_name']}")
            ...     print(f"Saved: {session['rows_saved']}")
            'Parser: HANA'
            'File: hana_statement.xls'
            'Saved: 85'

        Notes:
            - Returns None if session_id not found
            - Includes all session fields plus joined file/institution data
            - Useful for detailed session inspection
        """
        try:
            cursor = self.conn.execute('''
                SELECT
                    ps.*,
                    pf.file_name,
                    pf.file_hash,
                    fi.name as institution_name,
                    fi.institution_type
                FROM parsing_sessions ps
                JOIN processed_files pf ON ps.file_id = pf.id
                JOIN financial_institutions fi ON pf.institution_id = fi.id
                WHERE ps.id = ?
            ''', (session_id,))

            row = cursor.fetchone()
            if row:
                self.logger.debug(f'Retrieved parsing session {session_id}')
                return dict(row)
            else:
                self.logger.debug(f'Parsing session {session_id} not found')
                return None

        except Exception as e:
            self.logger.error(f'Error fetching parsing session {session_id}: {e}')
            raise


class SkippedTransactionRepository:
    """
    Repository for skipped transaction tracking during parsing.

    Manages storage and retrieval of transactions that were skipped during parsing,
    with reasons and metadata for debugging and validation reporting.

    Attributes:
        conn: SQLite database connection
        logger: Logger instance for operations tracking

    Examples:
        >>> repo = SkippedTransactionRepository(conn)
        >>> skipped_list = [
        ...     SkippedTransaction(row_number=5, skip_reason='zero_amount',
        ...                        merchant_name='Test', amount=0),
        ...     SkippedTransaction(row_number=10, skip_reason='invalid_date')
        ... ]
        >>> count = repo.batch_insert(session_id=1, skipped_list=skipped_list)
        >>> print(count)
        2
        >>> summary = repo.get_summary_by_reason(session_id=1)
        >>> print(summary[0])
        {'skip_reason': 'zero_amount', 'count': 1}
    """

    def __init__(self, connection: sqlite3.Connection):
        """
        Initialize repository with database connection.

        Args:
            connection: SQLite database connection instance
        """
        self.conn = connection
        self.logger = logging.getLogger(__name__)
        self.logger.debug('SkippedTransactionRepository initialized')

    def batch_insert(self, session_id: int, skipped_list: List[SkippedTransaction]) -> int:
        """
        Insert multiple skipped transactions for a parsing session.

        Loops through skipped transaction list and inserts each record.
        Serializes column_data as JSON for storage.

        Args:
            session_id: Foreign key to parsing_sessions table
            skipped_list: List of SkippedTransaction objects

        Returns:
            int: Number of skipped transactions inserted

        Examples:
            >>> from src.models import SkippedTransaction, SkipReason
            >>> repo = SkippedTransactionRepository(conn)
            >>> skipped = [
            ...     SkippedTransaction(
            ...         row_number=5,
            ...         skip_reason=SkipReason.ZERO_AMOUNT,
            ...         merchant_name='Test Store',
            ...         amount=0,
            ...         skip_details='Amount is zero',
            ...         column_data={'col1': 'value1', 'col2': 'value2'}
            ...     ),
            ...     SkippedTransaction(
            ...         row_number=10,
            ...         skip_reason=SkipReason.INVALID_DATE,
            ...         skip_details='Date format invalid'
            ...     )
            ... ]
            >>> count = repo.batch_insert(session_id=1, skipped_list=skipped)
            >>> print(count)
            2

        Notes:
            - Uses individual INSERT for each skipped transaction
            - Serializes column_data dict as JSON string
            - All inserts in single transaction (single commit)
            - Returns count of successful inserts
            - Rolls back on any error
        """
        if not skipped_list:
            self.logger.debug(f'No skipped transactions to insert for session_id={session_id}')
            return 0

        count = 0
        try:
            for skipped in skipped_list:
                # Serialize column_data as JSON
                column_data_json = json.dumps(skipped.column_data) if skipped.column_data else None

                self.conn.execute('''
                    INSERT INTO skipped_transactions (
                        session_id,
                        row_number,
                        skip_reason,
                        transaction_date,
                        merchant_name,
                        amount,
                        original_amount,
                        skip_details,
                        column_data
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ''', (
                    session_id,
                    skipped.row_number,
                    skipped.skip_reason,
                    skipped.transaction_date,
                    skipped.merchant_name,
                    skipped.amount,
                    skipped.original_amount,
                    skipped.skip_details,
                    column_data_json
                ))
                count += 1

            self.conn.commit()
            self.logger.info(f'Batch inserted {count} skipped transactions for session_id={session_id}')

        except Exception as e:
            self.conn.rollback()
            self.logger.error(f'Batch insert of skipped transactions failed for session_id={session_id}: {e}')
            raise

        return count

    def get_by_session(self, session_id: int) -> List[dict]:
        """
        Get all skipped transactions for a parsing session.

        Retrieves skipped transactions ordered by row number.
        Useful for detailed validation reports.

        Args:
            session_id: Session ID to query

        Returns:
            List of skipped transaction dictionaries ordered by row number

        Examples:
            >>> repo = SkippedTransactionRepository(conn)
            >>> skipped = repo.get_by_session(session_id=1)
            >>> for item in skipped:
            ...     print(f"Row {item['row_number']}: {item['skip_reason']}")
            'Row 5: zero_amount'
            'Row 10: invalid_date'
            'Row 15: missing_merchant'

        Notes:
            - Ordered by row_number ASC for sequential inspection
            - Returns all fields including serialized column_data (as JSON string)
            - Returns empty list if no skipped transactions found
        """
        try:
            cursor = self.conn.execute('''
                SELECT * FROM skipped_transactions
                WHERE session_id = ?
                ORDER BY row_number
            ''', (session_id,))

            results = [dict(row) for row in cursor.fetchall()]
            self.logger.debug(f'Retrieved {len(results)} skipped transactions for session_id={session_id}')
            return results

        except Exception as e:
            self.logger.error(f'Error fetching skipped transactions for session_id={session_id}: {e}')
            raise

    def get_summary_by_reason(self, session_id: int) -> List[dict]:
        """
        Get aggregated summary of skipped transactions by reason.

        Groups skipped transactions by skip_reason and counts occurrences.
        Useful for validation reports and identifying common parsing issues.

        Args:
            session_id: Session ID to query

        Returns:
            List of dicts with 'skip_reason' and 'count' keys, ordered by count descending

        Examples:
            >>> repo = SkippedTransactionRepository(conn)
            >>> summary = repo.get_summary_by_reason(session_id=1)
            >>> for item in summary:
            ...     print(f"{item['skip_reason']}: {item['count']} transactions")
            'zero_amount: 15 transactions'
            'invalid_date: 5 transactions'
            'missing_merchant: 2 transactions'

        Notes:
            - Groups by skip_reason
            - Counts occurrences for each reason
            - Ordered by count DESC (most common reasons first)
            - Returns empty list if no skipped transactions found
            - Useful for identifying systematic parsing issues
        """
        try:
            cursor = self.conn.execute('''
                SELECT skip_reason, COUNT(*) as count
                FROM skipped_transactions
                WHERE session_id = ?
                GROUP BY skip_reason
                ORDER BY count DESC
            ''', (session_id,))

            results = [dict(row) for row in cursor.fetchall()]
            self.logger.debug(f'Retrieved skip reason summary for session_id={session_id}: {len(results)} reasons')
            return results

        except Exception as e:
            self.logger.error(f'Error fetching skip reason summary for session_id={session_id}: {e}')
            raise


class UserRepository:
    """
    Repository for user account management with OAuth token handling.

    Manages user accounts for Google OAuth authentication including profile
    information, encrypted tokens, and session tracking.

    SECURITY NOTE: Tokens stored in database must be encrypted by application
    layer before insertion. This repository handles storage only, not encryption.

    Attributes:
        conn: SQLite database connection
        logger: Logger instance for operations tracking

    Examples:
        >>> repo = UserRepository(conn)
        >>> user_id = repo.create_user(
        ...     email='user@example.com',
        ...     google_id='123456',
        ...     name='John Doe',
        ...     profile_picture_url='https://...'
        ... )
        >>> user = repo.get_by_email('user@example.com')
        >>> print(user['name'])
        'John Doe'
    """

    def __init__(self, connection: sqlite3.Connection):
        """
        Initialize repository with database connection.

        Args:
            connection: SQLite database connection instance
        """
        self.conn = connection
        self.logger = logging.getLogger(__name__)
        self.logger.debug('UserRepository initialized')

    def create_user(self, email: str, google_id: str, name: str,
                   profile_picture_url: Optional[str] = None,
                   access_token: Optional[str] = None,
                   refresh_token: Optional[str] = None,
                   token_expires_at: Optional[str] = None) -> int:
        """
        Create a new user account.

        SECURITY: Tokens should be encrypted before passing to this method.

        Args:
            email: User's Google account email (unique)
            google_id: Google user ID (unique)
            name: User's display name
            profile_picture_url: Optional profile picture URL
            access_token: Optional encrypted access token
            refresh_token: Optional encrypted refresh token
            token_expires_at: Optional token expiration datetime (ISO format)

        Returns:
            int: User ID (lastrowid)

        Raises:
            sqlite3.IntegrityError: If email or google_id already exists

        Examples:
            >>> repo = UserRepository(conn)
            >>> user_id = repo.create_user(
            ...     email='user@example.com',
            ...     google_id='123456',
            ...     name='John Doe',
            ...     profile_picture_url='https://example.com/photo.jpg',
            ...     access_token='encrypted_token_here',
            ...     refresh_token='encrypted_refresh_token_here',
            ...     token_expires_at='2026-01-11T12:00:00'
            ... )
            >>> print(f'Created user with ID: {user_id}')

        Notes:
            - Sets is_active=1 by default
            - Sets created_at and updated_at automatically
            - Sets last_login_at to NULL (updated via update_last_login)
            - Token encryption is caller's responsibility
        """
        try:
            current_time = datetime.now().isoformat()
            cursor = self.conn.execute('''
                INSERT INTO users (
                    email,
                    google_id,
                    name,
                    profile_picture_url,
                    access_token,
                    refresh_token,
                    token_expires_at,
                    is_active,
                    created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?)
            ''', (
                email,
                google_id,
                name,
                profile_picture_url,
                access_token,
                refresh_token,
                token_expires_at,
                current_time
            ))

            self.conn.commit()

            self.logger.info(
                f'Created user: email={email}, google_id={google_id}, user_id={cursor.lastrowid}'
            )
            return cursor.lastrowid

        except sqlite3.IntegrityError as e:
            self.logger.error(f'Failed to create user (duplicate): {email} - {e}')
            raise
        except Exception as e:
            self.logger.error(f'Error creating user {email}: {e}')
            raise

    def get_by_id(self, user_id: int) -> Optional[dict]:
        """
        Get user by ID.

        Args:
            user_id: User ID

        Returns:
            User dict or None if not found

        Examples:
            >>> repo = UserRepository(conn)
            >>> user = repo.get_by_id(1)
            >>> if user:
            ...     print(f"User: {user['name']} ({user['email']})")

        Notes:
            - Returns all fields including encrypted tokens
            - Decryption is caller's responsibility
        """
        try:
            cursor = self.conn.execute(
                'SELECT * FROM users WHERE id = ?',
                (user_id,)
            )
            row = cursor.fetchone()
            return dict(row) if row else None
        except Exception as e:
            self.logger.error(f'Error fetching user by ID {user_id}: {e}')
            raise

    def get_by_email(self, email: str) -> Optional[dict]:
        """
        Get user by email address.

        Fast lookup using UNIQUE index on email column.

        Args:
            email: User's email address

        Returns:
            User dict or None if not found

        Examples:
            >>> repo = UserRepository(conn)
            >>> user = repo.get_by_email('user@example.com')
            >>> if user:
            ...     print(f"Found user: {user['name']}")
            ... else:
            ...     print("User not found")

        Notes:
            - Uses UNIQUE index for O(1) lookup
            - Returns all fields including encrypted tokens
        """
        try:
            cursor = self.conn.execute(
                'SELECT * FROM users WHERE email = ?',
                (email,)
            )
            row = cursor.fetchone()
            return dict(row) if row else None
        except Exception as e:
            self.logger.error(f'Error fetching user by email {email}: {e}')
            raise

    def get_by_google_id(self, google_id: str) -> Optional[dict]:
        """
        Get user by Google ID.

        Fast lookup using UNIQUE index on google_id column.

        Args:
            google_id: Google user ID

        Returns:
            User dict or None if not found

        Examples:
            >>> repo = UserRepository(conn)
            >>> user = repo.get_by_google_id('123456')
            >>> if user:
            ...     print(f"Found user: {user['email']}")

        Notes:
            - Uses UNIQUE index for O(1) lookup
            - Primary lookup method during OAuth callback
        """
        try:
            cursor = self.conn.execute(
                'SELECT * FROM users WHERE google_id = ?',
                (google_id,)
            )
            row = cursor.fetchone()
            return dict(row) if row else None
        except Exception as e:
            self.logger.error(f'Error fetching user by google_id {google_id}: {e}')
            raise

    def update_tokens(self, user_id: int, access_token: str,
                     refresh_token: Optional[str] = None,
                     token_expires_at: Optional[str] = None):
        """
        Update OAuth tokens for user.

        SECURITY: Tokens should be encrypted before passing to this method.

        Args:
            user_id: User ID
            access_token: Encrypted access token
            refresh_token: Optional encrypted refresh token (None to keep existing)
            token_expires_at: Optional token expiration datetime (ISO format)

        Examples:
            >>> repo = UserRepository(conn)
            >>> repo.update_tokens(
            ...     user_id=1,
            ...     access_token='new_encrypted_token',
            ...     token_expires_at='2026-01-12T12:00:00'
            ... )

        Notes:
            - Automatically updates updated_at timestamp via trigger
            - If refresh_token is None, existing refresh_token is preserved
            - Token encryption is caller's responsibility
        """
        try:
            if refresh_token is not None:
                self.conn.execute('''
                    UPDATE users
                    SET access_token = ?,
                        refresh_token = ?,
                        token_expires_at = ?
                    WHERE id = ?
                ''', (access_token, refresh_token, token_expires_at, user_id))
            else:
                # Preserve existing refresh_token
                self.conn.execute('''
                    UPDATE users
                    SET access_token = ?,
                        token_expires_at = ?
                    WHERE id = ?
                ''', (access_token, token_expires_at, user_id))

            self.conn.commit()
            self.logger.debug(f'Updated tokens for user_id={user_id}')

        except Exception as e:
            self.logger.error(f'Error updating tokens for user_id={user_id}: {e}')
            raise

    def update_profile(self, user_id: int, name: Optional[str] = None,
                      profile_picture_url: Optional[str] = None):
        """
        Update user profile information.

        Args:
            user_id: User ID
            name: Optional new display name
            profile_picture_url: Optional new profile picture URL

        Examples:
            >>> repo = UserRepository(conn)
            >>> repo.update_profile(
            ...     user_id=1,
            ...     name='John Smith',
            ...     profile_picture_url='https://example.com/new_photo.jpg'
            ... )

        Notes:
            - Only updates provided fields (None values are skipped)
            - Automatically updates updated_at timestamp via trigger
        """
        try:
            updates = []
            params = []

            if name is not None:
                updates.append('name = ?')
                params.append(name)

            if profile_picture_url is not None:
                updates.append('profile_picture_url = ?')
                params.append(profile_picture_url)

            if not updates:
                self.logger.debug(f'No profile updates for user_id={user_id}')
                return

            params.append(user_id)
            sql = f"UPDATE users SET {', '.join(updates)} WHERE id = ?"

            self.conn.execute(sql, tuple(params))
            self.conn.commit()

            self.logger.debug(f'Updated profile for user_id={user_id}')

        except Exception as e:
            self.logger.error(f'Error updating profile for user_id={user_id}: {e}')
            raise

    def update_last_login(self, user_id: int):
        """
        Update last login timestamp.

        Call this after successful authentication.

        Args:
            user_id: User ID

        Examples:
            >>> repo = UserRepository(conn)
            >>> repo.update_last_login(user_id=1)

        Notes:
            - Sets last_login_at to current timestamp
            - Automatically updates updated_at timestamp via trigger
        """
        try:
            current_time = datetime.now().isoformat()
            self.conn.execute(
                'UPDATE users SET last_login_at = ? WHERE id = ?',
                (current_time, user_id)
            )
            self.conn.commit()
            self.logger.debug(f'Updated last_login for user_id={user_id}')

        except Exception as e:
            self.logger.error(f'Error updating last_login for user_id={user_id}: {e}')
            raise

    def deactivate_user(self, user_id: int):
        """
        Deactivate user account (soft delete).

        Sets is_active=0 without deleting the record.

        Args:
            user_id: User ID

        Examples:
            >>> repo = UserRepository(conn)
            >>> repo.deactivate_user(user_id=1)

        Notes:
            - Soft delete - user data is preserved
            - Automatically updates updated_at timestamp via trigger
            - Consider clearing tokens when deactivating
        """
        try:
            self.conn.execute(
                'UPDATE users SET is_active = 0 WHERE id = ?',
                (user_id,)
            )
            self.conn.commit()
            self.logger.info(f'Deactivated user_id={user_id}')

        except Exception as e:
            self.logger.error(f'Error deactivating user_id={user_id}: {e}')
            raise

    def reactivate_user(self, user_id: int):
        """
        Reactivate user account.

        Sets is_active=1 for previously deactivated user.

        Args:
            user_id: User ID

        Examples:
            >>> repo = UserRepository(conn)
            >>> repo.reactivate_user(user_id=1)

        Notes:
            - Automatically updates updated_at timestamp via trigger
            - User will need to re-authenticate for new tokens
        """
        try:
            self.conn.execute(
                'UPDATE users SET is_active = 1 WHERE id = ?',
                (user_id,)
            )
            self.conn.commit()
            self.logger.info(f'Reactivated user_id={user_id}')

        except Exception as e:
            self.logger.error(f'Error reactivating user_id={user_id}: {e}')
            raise

    def get_all_active_users(self, limit: int = 100, offset: int = 0) -> List[dict]:
        """
        Get all active users with pagination.

        Args:
            limit: Maximum number of users to return (default: 100)
            offset: Number of users to skip for pagination (default: 0)

        Returns:
            List of user dictionaries ordered by created_at DESC

        Examples:
            >>> repo = UserRepository(conn)
            >>> users = repo.get_all_active_users(limit=50)
            >>> for user in users:
            ...     print(f"{user['email']} - Last login: {user['last_login_at']}")

        Notes:
            - Only returns users where is_active=1
            - Ordered by created_at DESC (newest first)
            - Supports pagination via limit/offset
            - Uses indexed query (is_active index)
        """
        try:
            cursor = self.conn.execute('''
                SELECT * FROM users
                WHERE is_active = 1
                ORDER BY created_at DESC
                LIMIT ? OFFSET ?
            ''', (limit, offset))

            results = [dict(row) for row in cursor.fetchall()]
            self.logger.debug(f'Retrieved {len(results)} active users')
            return results

        except Exception as e:
            self.logger.error(f'Error fetching active users: {e}')
            raise

    def count_active_users(self) -> int:
        """
        Count total number of active users.

        Returns:
            Count of active users

        Examples:
            >>> repo = UserRepository(conn)
            >>> total = repo.count_active_users()
            >>> print(f'Total active users: {total}')

        Notes:
            - Uses indexed query (is_active index)
            - Useful for pagination calculations
        """
        try:
            cursor = self.conn.execute(
                'SELECT COUNT(*) FROM users WHERE is_active = 1'
            )
            return cursor.fetchone()[0]

        except Exception as e:
            self.logger.error(f'Error counting active users: {e}')
            raise


class CategoryMerchantMappingRepository:
    """
    Repository for category-merchant mapping management with smart lookup.

    Manages merchant pattern mappings to categories for automated transaction
    categorization. Supports both exact and partial matching strategies with
    confidence scoring for reliable auto-categorization.

    Attributes:
        conn: SQLite database connection
        logger: Logger instance for operations tracking

    Examples:
        >>> repo = CategoryMerchantMappingRepository(conn)
        >>> category_id = repo.get_category_by_merchant('스타벅스')
        >>> if category_id:
        ...     print(f'Merchant maps to category {category_id}')
        >>> # Add new mapping
        >>> mapping_id = repo.add_mapping(
        ...     category_id=1,
        ...     merchant_pattern='블루보틀',
        ...     match_type='exact',
        ...     confidence=100,
        ...     source='manual'
        ... )
    """

    def __init__(self, connection: sqlite3.Connection):
        """
        Initialize repository with database connection.

        Args:
            connection: SQLite database connection instance
        """
        self.conn = connection
        self.logger = logging.getLogger(__name__)
        self.logger.debug('CategoryMerchantMappingRepository initialized')

    def get_category_by_merchant(self, merchant_name: str) -> Optional[int]:
        """
        Get category_id for a merchant name using prioritized matching.

        Priority:
        1. Exact match (match_type='exact')
        2. Partial match (match_type='partial', using LIKE)

        Returns highest confidence match for each match type.
        Returns None if no match found.

        Args:
            merchant_name: Merchant name to look up

        Returns:
            category_id or None

        Examples:
            >>> repo = CategoryMerchantMappingRepository(conn)
            >>> category_id = repo.get_category_by_merchant('스타벅스')
            >>> if category_id:
            ...     print(f'Merchant categorized as {category_id}')
            ... else:
            ...     print('No mapping found')

        Notes:
            - First attempts exact match (fastest, O(1) via index)
            - Falls back to partial match if no exact match found
            - Returns highest confidence match for each strategy
            - Partial matches prefer longer patterns for specificity
        """
        try:
            # Strategy 1: Try exact match first (fastest, indexed lookup)
            cursor = self.conn.execute('''
                SELECT category_id
                FROM category_merchant_mappings
                WHERE merchant_pattern = ? AND match_type = 'exact'
                ORDER BY confidence DESC
                LIMIT 1
            ''', (merchant_name,))

            row = cursor.fetchone()
            if row:
                self.logger.debug(f'Exact match found for merchant: {merchant_name}')
                return row['category_id']

            # Strategy 2: Try partial match (fallback for variations)
            # Use LIKE with pattern length for specificity ranking
            cursor = self.conn.execute('''
                SELECT category_id
                FROM category_merchant_mappings
                WHERE match_type = 'partial' AND ? LIKE '%' || merchant_pattern || '%'
                ORDER BY confidence DESC, LENGTH(merchant_pattern) DESC
                LIMIT 1
            ''', (merchant_name,))

            row = cursor.fetchone()
            if row:
                self.logger.debug(f'Partial match found for merchant: {merchant_name}')
                return row['category_id']

            self.logger.debug(f'No mapping found for merchant: {merchant_name}')
            return None

        except Exception as e:
            self.logger.error(f'Error looking up merchant {merchant_name}: {e}')
            raise

    def add_mapping(
        self,
        category_id: int,
        merchant_pattern: str,
        match_type: str = 'exact',
        confidence: int = 100,
        source: str = 'manual'
    ) -> int:
        """
        Add a new category-merchant mapping.

        Uses INSERT OR REPLACE to handle duplicates gracefully, updating
        existing mappings with new confidence and source if conflict occurs.

        Args:
            category_id: Category to map to
            merchant_pattern: Merchant name or pattern
            match_type: 'exact' or 'partial'
            confidence: 0-100 confidence score
            source: Source of mapping (e.g., 'manual', 'imported')

        Returns:
            mapping_id

        Raises:
            ValueError: If match_type is invalid or confidence out of range

        Examples:
            >>> repo = CategoryMerchantMappingRepository(conn)
            >>> mapping_id = repo.add_mapping(
            ...     category_id=1,
            ...     merchant_pattern='블루보틀',
            ...     match_type='exact',
            ...     confidence=100,
            ...     source='manual'
            ... )
            >>> print(f'Created mapping with ID: {mapping_id}')

        Notes:
            - Validates match_type and confidence before insert
            - Uses INSERT OR REPLACE for idempotent operation
            - Updates updated_at timestamp via trigger on conflict
            - Commits immediately (single transaction)
        """
        # Validate inputs
        if match_type not in ('exact', 'partial'):
            raise ValueError(f"Invalid match_type: {match_type}. Must be 'exact' or 'partial'")

        if not (0 <= confidence <= 100):
            raise ValueError(f"Invalid confidence: {confidence}. Must be between 0 and 100")

        try:
            cursor = self.conn.execute('''
                INSERT INTO category_merchant_mappings (
                    category_id,
                    merchant_pattern,
                    match_type,
                    confidence,
                    source
                ) VALUES (?, ?, ?, ?, ?)
                ON CONFLICT (category_id, merchant_pattern, match_type) DO UPDATE SET
                    confidence = excluded.confidence,
                    source = excluded.source,
                    updated_at = CURRENT_TIMESTAMP
            ''', (category_id, merchant_pattern, match_type, confidence, source))

            self.conn.commit()

            # Get the mapping_id (either new or existing)
            if cursor.lastrowid > 0:
                mapping_id = cursor.lastrowid
                self.logger.info(
                    f'Added mapping: category_id={category_id}, pattern={merchant_pattern}, '
                    f'type={match_type}, id={mapping_id}'
                )
            else:
                # Fetch existing ID on conflict
                cursor = self.conn.execute('''
                    SELECT id FROM category_merchant_mappings
                    WHERE category_id = ? AND merchant_pattern = ? AND match_type = ?
                ''', (category_id, merchant_pattern, match_type))
                row = cursor.fetchone()
                mapping_id = row['id'] if row else 0
                self.logger.info(
                    f'Updated existing mapping: category_id={category_id}, pattern={merchant_pattern}, '
                    f'type={match_type}, id={mapping_id}'
                )

            return mapping_id

        except Exception as e:
            self.logger.error(
                f'Error adding mapping: category_id={category_id}, pattern={merchant_pattern} - {e}'
            )
            raise

    def update_mapping(
        self,
        mapping_id: int,
        category_id: Optional[int] = None,
        confidence: Optional[int] = None
    ) -> bool:
        """
        Update an existing mapping.

        Allows partial updates (only provided fields are updated).
        Automatically updates updated_at timestamp via trigger.

        Args:
            mapping_id: ID of mapping to update
            category_id: New category_id (optional)
            confidence: New confidence score (optional)

        Returns:
            True if updated, False if not found

        Raises:
            ValueError: If confidence out of range

        Examples:
            >>> repo = CategoryMerchantMappingRepository(conn)
            >>> # Update only confidence
            >>> success = repo.update_mapping(mapping_id=1, confidence=95)
            >>> print(f'Update success: {success}')
            >>> # Update only category
            >>> success = repo.update_mapping(mapping_id=1, category_id=5)
            >>> # Update both
            >>> success = repo.update_mapping(mapping_id=1, category_id=5, confidence=90)

        Notes:
            - Only updates provided fields (None values skipped)
            - Returns False if mapping_id doesn't exist
            - Validates confidence range if provided
            - Commits immediately
        """
        # Validate confidence if provided
        if confidence is not None and not (0 <= confidence <= 100):
            raise ValueError(f"Invalid confidence: {confidence}. Must be between 0 and 100")

        # Build dynamic update query
        updates = []
        params = []

        if category_id is not None:
            updates.append('category_id = ?')
            params.append(category_id)

        if confidence is not None:
            updates.append('confidence = ?')
            params.append(confidence)

        if not updates:
            self.logger.debug(f'No updates provided for mapping_id={mapping_id}')
            return False

        params.append(mapping_id)

        try:
            sql = f"UPDATE category_merchant_mappings SET {', '.join(updates)} WHERE id = ?"
            cursor = self.conn.execute(sql, tuple(params))
            self.conn.commit()

            if cursor.rowcount > 0:
                self.logger.info(f'Updated mapping_id={mapping_id}: {updates}')
                return True
            else:
                self.logger.debug(f'Mapping not found: mapping_id={mapping_id}')
                return False

        except Exception as e:
            self.logger.error(f'Error updating mapping_id={mapping_id}: {e}')
            raise

    def delete_mapping(self, mapping_id: int) -> bool:
        """
        Delete a mapping.

        Permanently removes mapping from database. Use with caution
        as this affects auto-categorization behavior.

        Args:
            mapping_id: ID of mapping to delete

        Returns:
            True if deleted, False if not found

        Examples:
            >>> repo = CategoryMerchantMappingRepository(conn)
            >>> success = repo.delete_mapping(mapping_id=1)
            >>> if success:
            ...     print('Mapping deleted successfully')
            ... else:
            ...     print('Mapping not found')

        Notes:
            - Permanent deletion (no soft delete)
            - Returns False if mapping_id doesn't exist
            - Commits immediately
            - Consider archiving instead for audit trail
        """
        try:
            cursor = self.conn.execute(
                'DELETE FROM category_merchant_mappings WHERE id = ?',
                (mapping_id,)
            )
            self.conn.commit()

            if cursor.rowcount > 0:
                self.logger.info(f'Deleted mapping_id={mapping_id}')
                return True
            else:
                self.logger.debug(f'Mapping not found for deletion: mapping_id={mapping_id}')
                return False

        except Exception as e:
            self.logger.error(f'Error deleting mapping_id={mapping_id}: {e}')
            raise

    def get_all(self, category_id: Optional[int] = None) -> List[Dict]:
        """
        Get all mappings, optionally filtered by category.

        Joins with categories table to include category name for readability.
        Useful for management UI and reporting.

        Args:
            category_id: Filter by category (optional)

        Returns:
            List of dicts with keys: id, category_id, category_name,
                                    merchant_pattern, match_type, confidence, source

        Examples:
            >>> repo = CategoryMerchantMappingRepository(conn)
            >>> # Get all mappings
            >>> all_mappings = repo.get_all()
            >>> print(f'Total mappings: {len(all_mappings)}')
            >>> # Get mappings for specific category
            >>> food_mappings = repo.get_all(category_id=1)
            >>> for mapping in food_mappings:
            ...     print(f"{mapping['merchant_pattern']} -> {mapping['category_name']}")

        Notes:
            - Returns all fields including confidence and source
            - Joins with categories for category_name
            - Ordered by category name, then confidence descending
            - No pagination (use with caution on large datasets)
        """
        try:
            if category_id is not None:
                cursor = self.conn.execute('''
                    SELECT
                        cm.id,
                        cm.category_id,
                        c.name as category_name,
                        cm.merchant_pattern,
                        cm.match_type,
                        cm.confidence,
                        cm.source
                    FROM category_merchant_mappings cm
                    JOIN categories c ON cm.category_id = c.id
                    WHERE cm.category_id = ?
                    ORDER BY cm.confidence DESC, cm.merchant_pattern
                ''', (category_id,))
            else:
                cursor = self.conn.execute('''
                    SELECT
                        cm.id,
                        cm.category_id,
                        c.name as category_name,
                        cm.merchant_pattern,
                        cm.match_type,
                        cm.confidence,
                        cm.source
                    FROM category_merchant_mappings cm
                    JOIN categories c ON cm.category_id = c.id
                    ORDER BY c.name, cm.confidence DESC, cm.merchant_pattern
                ''')

            results = [dict(row) for row in cursor.fetchall()]
            self.logger.debug(f'Retrieved {len(results)} mappings (category_id={category_id})')
            return results

        except Exception as e:
            self.logger.error(f'Error fetching mappings (category_id={category_id}): {e}')
            raise

    def get_mappings_by_pattern(self, pattern: str) -> List[Dict]:
        """
        Search mappings by merchant pattern (partial match).

        Case-insensitive search for management and debugging.
        Joins with categories for category names.

        Args:
            pattern: Search pattern (case-insensitive)

        Returns:
            List of matching mappings with category names

        Examples:
            >>> repo = CategoryMerchantMappingRepository(conn)
            >>> # Search for all Starbucks variations
            >>> results = repo.get_mappings_by_pattern('스타벅스')
            >>> for mapping in results:
            ...     print(f"{mapping['merchant_pattern']} -> {mapping['category_name']}")
            '스타벅스' -> '카페/간식'
            '스타벅스 강남점' -> '카페/간식'

        Notes:
            - Case-insensitive search using LIKE
            - Returns all fields with joined category names
            - Ordered by confidence descending
            - Useful for finding duplicate or similar patterns
        """
        try:
            cursor = self.conn.execute('''
                SELECT
                    cm.id,
                    cm.category_id,
                    c.name as category_name,
                    cm.merchant_pattern,
                    cm.match_type,
                    cm.confidence,
                    cm.source
                FROM category_merchant_mappings cm
                JOIN categories c ON cm.category_id = c.id
                WHERE cm.merchant_pattern LIKE ?
                ORDER BY cm.confidence DESC, cm.merchant_pattern
            ''', (f'%{pattern}%',))

            results = [dict(row) for row in cursor.fetchall()]
            self.logger.debug(f'Found {len(results)} mappings matching pattern: {pattern}')
            return results

        except Exception as e:
            self.logger.error(f'Error searching mappings by pattern {pattern}: {e}')
            raise


class DuplicateConfirmationRepository:
    """
    Repository for duplicate transaction confirmation management.

    Manages duplicate transaction confirmations that require user review before
    insertion. Tracks potential duplicates detected during parsing with metadata
    about match confidence, matched fields, and user decisions.

    Attributes:
        conn: SQLite database connection
        logger: Logger instance for operations tracking

    Examples:
        >>> repo = DuplicateConfirmationRepository(conn)
        >>> confirmation_id = repo.create_confirmation(
        ...     session_id=1,
        ...     new_transaction_data='{"date": "2025.09.13", "item": "스타벅스", ...}',
        ...     new_transaction_index=5,
        ...     existing_transaction_id=123,
        ...     confidence_score=85,
        ...     match_fields='["date", "amount", "merchant"]',
        ...     difference_summary='Same date and amount, similar merchant name'
        ... )
        >>> confirmations = repo.get_by_session(session_id=1)
        >>> repo.apply_user_decision(confirmation_id, 'insert', 'user@example.com')
    """

    def __init__(self, conn: sqlite3.Connection):
        """
        Initialize repository with database connection.

        Args:
            conn: SQLite database connection instance
        """
        self.conn = conn
        self.logger = logging.getLogger(__name__)
        self.logger.debug('DuplicateConfirmationRepository initialized')

    def create_confirmation(
        self,
        session_id: int,
        new_transaction_data: str,
        new_transaction_index: int,
        existing_transaction_id: int,
        confidence_score: int,
        match_fields: str,
        difference_summary: str
    ) -> int:
        """
        Create a new duplicate confirmation record.

        Creates a pending confirmation for a potential duplicate transaction
        that requires user review. Sets expiration to 30 days from creation.

        Args:
            session_id: Foreign key to parsing_sessions table
            new_transaction_data: JSON serialized transaction data (not yet inserted)
            new_transaction_index: Index of transaction in parsing batch
            existing_transaction_id: Foreign key to existing transaction in DB
            confidence_score: Match confidence (0-100)
            match_fields: JSON array of matched field names (e.g., '["date", "amount"]')
            difference_summary: Human-readable summary of differences

        Returns:
            int: Confirmation ID (lastrowid)

        Raises:
            ValueError: If confidence_score out of valid range (0-100)

        Examples:
            >>> repo = DuplicateConfirmationRepository(conn)
            >>> confirmation_id = repo.create_confirmation(
            ...     session_id=1,
            ...     new_transaction_data='{"date": "2025.09.13", "item": "스타벅스", ...}',
            ...     new_transaction_index=5,
            ...     existing_transaction_id=123,
            ...     confidence_score=85,
            ...     match_fields='["date", "amount", "merchant"]',
            ...     difference_summary='Same date and amount, similar merchant name'
            ... )
            >>> print(confirmation_id)
            1

        Notes:
            - Status automatically set to 'pending'
            - created_at set to current timestamp
            - expires_at set to 30 days from creation
            - Commits immediately (single transaction)
        """
        # Validate confidence_score
        if not (0 <= confidence_score <= 100):
            raise ValueError(f"Invalid confidence_score: {confidence_score}. Must be between 0 and 100")

        try:
            from datetime import timedelta
            created_at = datetime.now()
            expires_at = created_at + timedelta(days=30)

            cursor = self.conn.execute('''
                INSERT INTO duplicate_transaction_confirmations (
                    session_id,
                    new_transaction_data,
                    new_transaction_index,
                    existing_transaction_id,
                    confidence_score,
                    match_fields,
                    difference_summary,
                    status,
                    created_at,
                    expires_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?)
            ''', (
                session_id,
                new_transaction_data,
                new_transaction_index,
                existing_transaction_id,
                confidence_score,
                match_fields,
                difference_summary,
                created_at.isoformat(),
                expires_at.isoformat()
            ))

            self.conn.commit()

            self.logger.debug(
                f'Created duplicate confirmation: session_id={session_id}, '
                f'new_index={new_transaction_index}, existing_id={existing_transaction_id}, '
                f'confidence={confidence_score}, confirmation_id={cursor.lastrowid}'
            )
            return cursor.lastrowid

        except Exception as e:
            self.logger.error(
                f'Error creating duplicate confirmation for session_id={session_id}: {e}'
            )
            raise

    def get_by_session(self, session_id: int) -> List[dict]:
        """
        Get all duplicate confirmations for a parsing session.

        Retrieves all confirmations with full details including both new transaction
        data and existing transaction details via JOIN. Ordered by new_transaction_index
        for sequential review.

        Args:
            session_id: Session ID to query

        Returns:
            List of confirmation dictionaries with joined transaction details

        Examples:
            >>> repo = DuplicateConfirmationRepository(conn)
            >>> confirmations = repo.get_by_session(session_id=1)
            >>> for conf in confirmations:
            ...     print(f"Confirmation {conf['id']}: {conf['status']}")
            ...     print(f"  New: {conf['new_transaction_data']}")
            ...     print(f"  Existing: {conf['existing_merchant_name']}")

        Notes:
            - Joins with transactions table for existing transaction details
            - Returns both new_transaction_data (JSON) and existing transaction fields
            - Ordered by new_transaction_index ASC for sequential review
            - Returns empty list if no confirmations found
        """
        try:
            cursor = self.conn.execute('''
                SELECT
                    dc.*,
                    t.transaction_date as existing_transaction_date,
                    t.merchant_name as existing_merchant_name,
                    t.amount as existing_amount,
                    t.category_id as existing_category_id,
                    t.institution_id as existing_institution_id,
                    t.installment_months as existing_installment_months,
                    t.installment_current as existing_installment_current,
                    t.original_amount as existing_original_amount,
                    c.name as existing_category_name,
                    fi.name as existing_institution_name
                FROM duplicate_transaction_confirmations dc
                JOIN transactions t ON dc.existing_transaction_id = t.id
                JOIN categories c ON t.category_id = c.id
                JOIN financial_institutions fi ON t.institution_id = fi.id
                WHERE dc.session_id = ?
                ORDER BY dc.new_transaction_index ASC
            ''', (session_id,))

            results = [dict(row) for row in cursor.fetchall()]
            self.logger.debug(
                f'Retrieved {len(results)} duplicate confirmations for session_id={session_id}'
            )
            return results

        except Exception as e:
            self.logger.error(
                f'Error fetching duplicate confirmations for session_id={session_id}: {e}'
            )
            raise

    def get_pending_count_by_session(self, session_id: int) -> int:
        """
        Count pending duplicate confirmations for a session.

        Fast count query using indexed lookup on session_id and status.

        Args:
            session_id: Session ID to query

        Returns:
            Count of pending confirmations

        Examples:
            >>> repo = DuplicateConfirmationRepository(conn)
            >>> pending_count = repo.get_pending_count_by_session(session_id=1)
            >>> print(f'Pending confirmations: {pending_count}')
            5

        Notes:
            - Uses indexed query (session_id and status indexes)
            - Only counts status='pending' confirmations
            - Useful for session completion checks
        """
        try:
            cursor = self.conn.execute('''
                SELECT COUNT(*) as count
                FROM duplicate_transaction_confirmations
                WHERE session_id = ? AND status = 'pending'
            ''', (session_id,))

            count = cursor.fetchone()['count']
            self.logger.debug(
                f'Found {count} pending confirmations for session_id={session_id}'
            )
            return count

        except Exception as e:
            self.logger.error(
                f'Error counting pending confirmations for session_id={session_id}: {e}'
            )
            raise

    def apply_user_decision(
        self,
        confirmation_id: int,
        action: str,
        user_id: str
    ) -> dict:
        """
        Apply user's decision to a duplicate confirmation.

        Updates confirmation with user's decision and executes the action:
        - 'insert': Inserts new transaction into transactions table
        - 'skip': Marks as confirmed_skip (no insertion)
        - 'merge': Marks as confirmed_merge (future: merge logic)

        Args:
            confirmation_id: Confirmation ID to update
            action: User action - 'insert', 'skip', or 'merge'
            user_id: User identifier (email or user ID string)

        Returns:
            Updated confirmation record dict

        Raises:
            ValueError: If action is invalid or confirmation not found
            Exception: If transaction insertion fails

        Examples:
            >>> repo = DuplicateConfirmationRepository(conn)
            >>> # User decides to insert the new transaction
            >>> updated = repo.apply_user_decision(
            ...     confirmation_id=1,
            ...     action='insert',
            ...     user_id='user@example.com'
            ... )
            >>> print(f"Status: {updated['status']}")
            'confirmed_insert'

            >>> # User decides to skip (it's a duplicate)
            >>> updated = repo.apply_user_decision(
            ...     confirmation_id=2,
            ...     action='skip',
            ...     user_id='user@example.com'
            ... )
            >>> print(f"Status: {updated['status']}")
            'confirmed_skip'

        Notes:
            - Validates action is one of: 'insert', 'skip', 'merge'
            - Uses database transaction for atomicity
            - Rollback on any error (e.g., insertion failure)
            - Commits immediately on success
            - For 'insert': Parses new_transaction_data JSON and inserts via TransactionRepository
            - For 'skip': Only updates confirmation status
            - For 'merge': Marks as confirmed_merge (actual merge logic is future work)
        """
        # Validate action
        valid_actions = ('insert', 'skip', 'merge')
        if action not in valid_actions:
            raise ValueError(
                f"Invalid action: {action}. Must be one of {valid_actions}"
            )

        try:
            # Get confirmation record
            cursor = self.conn.execute(
                'SELECT * FROM duplicate_transaction_confirmations WHERE id = ?',
                (confirmation_id,)
            )
            row = cursor.fetchone()
            if not row:
                raise ValueError(f'Confirmation not found: confirmation_id={confirmation_id}')

            confirmation = dict(row)
            decided_at = datetime.now().isoformat()

            # Update confirmation status
            self.conn.execute('''
                UPDATE duplicate_transaction_confirmations
                SET user_action = ?,
                    status = ?,
                    user_id = ?,
                    decided_at = ?
                WHERE id = ?
            ''', (
                action,
                f'confirmed_{action}',
                user_id,
                decided_at,
                confirmation_id
            ))

            # Execute action based on user decision
            if action == 'insert':
                # Parse new_transaction_data JSON and insert transaction
                new_txn_data = json.loads(confirmation['new_transaction_data'])

                # Create Transaction object from JSON data
                txn = Transaction(
                    month=new_txn_data['month'],
                    date=new_txn_data['date'],
                    category=new_txn_data['category'],
                    item=new_txn_data['item'],
                    amount=new_txn_data['amount'],
                    source=new_txn_data['source'],
                    installment_months=new_txn_data.get('installment_months'),
                    installment_current=new_txn_data.get('installment_current'),
                    original_amount=new_txn_data.get('original_amount')
                )

                # Insert transaction using TransactionRepository
                # Note: We need the category_repo and institution_repo for this
                # For now, we'll create them inline (could be passed as dependencies)
                from src.db.repository import CategoryRepository, InstitutionRepository, TransactionRepository

                category_repo = CategoryRepository(self.conn)
                institution_repo = InstitutionRepository(self.conn)
                txn_repo = TransactionRepository(self.conn, category_repo, institution_repo)

                # Get session info to associate file_id if available
                cursor = self.conn.execute(
                    'SELECT file_id FROM parsing_sessions WHERE id = ?',
                    (confirmation['session_id'],)
                )
                session_row = cursor.fetchone()
                file_id = session_row['file_id'] if session_row else None

                # Insert transaction (auto_commit=False since we're in a transaction)
                txn_id = txn_repo.insert(
                    txn,
                    auto_commit=False,
                    file_id=file_id,
                    row_number=confirmation['new_transaction_index']
                )

                self.logger.info(
                    f'Inserted transaction {txn_id} from confirmation {confirmation_id}'
                )

            elif action == 'skip':
                # No additional action needed - just status update
                self.logger.info(
                    f'Skipped transaction from confirmation {confirmation_id}'
                )

            elif action == 'merge':
                # Placeholder for future merge logic
                # For now, just mark as confirmed_merge
                self.logger.info(
                    f'Marked confirmation {confirmation_id} for merge (merge logic not yet implemented)'
                )

            # Commit transaction
            self.conn.commit()

            # Fetch and return updated confirmation
            cursor = self.conn.execute(
                'SELECT * FROM duplicate_transaction_confirmations WHERE id = ?',
                (confirmation_id,)
            )
            updated = dict(cursor.fetchone())

            self.logger.info(
                f'Applied user decision: confirmation_id={confirmation_id}, '
                f'action={action}, user_id={user_id}'
            )

            return updated

        except Exception as e:
            self.conn.rollback()
            self.logger.error(
                f'Error applying user decision for confirmation_id={confirmation_id}: {e}'
            )
            raise

    def get_by_id(self, confirmation_id: int) -> Optional[dict]:
        """
        Get a single duplicate confirmation by ID.

        Args:
            confirmation_id: Confirmation ID

        Returns:
            Confirmation dict or None if not found

        Examples:
            >>> repo = DuplicateConfirmationRepository(conn)
            >>> conf = repo.get_by_id(1)
            >>> if conf:
            ...     print(f"Status: {conf['status']}")
            ...     print(f"Confidence: {conf['confidence_score']}")

        Notes:
            - Returns all fields including JSON data
            - Returns None if confirmation_id not found
        """
        try:
            cursor = self.conn.execute(
                'SELECT * FROM duplicate_transaction_confirmations WHERE id = ?',
                (confirmation_id,)
            )
            row = cursor.fetchone()
            return dict(row) if row else None

        except Exception as e:
            self.logger.error(
                f'Error fetching duplicate confirmation by ID {confirmation_id}: {e}'
            )
            raise

    def cleanup_expired(self) -> int:
        """
        Mark expired pending confirmations as expired.

        Updates status to 'expired' for all pending confirmations where
        expires_at < current timestamp. Called periodically for cleanup.

        Returns:
            Count of expired confirmations

        Examples:
            >>> repo = DuplicateConfirmationRepository(conn)
            >>> expired_count = repo.cleanup_expired()
            >>> print(f'Expired {expired_count} confirmations')

        Notes:
            - Only affects status='pending' confirmations
            - Uses expires_at index for efficient query
            - Commits immediately
            - Should be called periodically (e.g., daily cron job)
        """
        try:
            current_time = datetime.now().isoformat()
            cursor = self.conn.execute('''
                UPDATE duplicate_transaction_confirmations
                SET status = 'expired'
                WHERE status = 'pending' AND expires_at < ?
            ''', (current_time,))

            self.conn.commit()
            expired_count = cursor.rowcount

            if expired_count > 0:
                self.logger.info(f'Expired {expired_count} pending confirmations')
            else:
                self.logger.debug('No expired confirmations found')

            return expired_count

        except Exception as e:
            self.logger.error(f'Error cleaning up expired confirmations: {e}')
            raise

    def get_all_pending(self) -> List[dict]:
        """
        Get all pending confirmations across all sessions.

        Retrieves all pending confirmations with session and file context.
        Useful for global pending review queue.

        Returns:
            List of pending confirmations with session and file details

        Examples:
            >>> repo = DuplicateConfirmationRepository(conn)
            >>> all_pending = repo.get_all_pending()
            >>> print(f'Total pending: {len(all_pending)}')
            >>> for conf in all_pending:
            ...     print(f"Session {conf['session_id']}: {conf['file_name']}")

        Notes:
            - Only returns status='pending' confirmations
            - Joins with parsing_sessions and processed_files for context
            - Ordered by created_at DESC (most recent first)
            - No pagination (use with caution on large datasets)
        """
        try:
            cursor = self.conn.execute('''
                SELECT
                    dc.*,
                    ps.parser_type,
                    pf.file_name,
                    pf.processed_at as file_processed_at,
                    t.transaction_date as existing_transaction_date,
                    t.merchant_name as existing_merchant_name,
                    t.amount as existing_amount,
                    t.category_id as existing_category_id,
                    t.institution_id as existing_institution_id,
                    t.installment_months as existing_installment_months,
                    t.installment_current as existing_installment_current,
                    t.original_amount as existing_original_amount,
                    c.name as existing_category_name,
                    fi.name as existing_institution_name
                FROM duplicate_transaction_confirmations dc
                JOIN parsing_sessions ps ON dc.session_id = ps.id
                JOIN processed_files pf ON ps.file_id = pf.id
                JOIN transactions t ON dc.existing_transaction_id = t.id
                JOIN categories c ON t.category_id = c.id
                JOIN financial_institutions fi ON t.institution_id = fi.id
                WHERE dc.status = 'pending'
                ORDER BY dc.created_at DESC
            ''')

            results = [dict(row) for row in cursor.fetchall()]
            self.logger.debug(f'Retrieved {len(results)} pending confirmations across all sessions')
            return results

        except Exception as e:
            self.logger.error(f'Error fetching all pending confirmations: {e}')
            raise

    def bulk_confirm_session(
        self,
        session_id: int,
        action: str,
        user_id: str
    ) -> int:
        """
        Apply same action to all pending confirmations in a session.

        Convenience method for bulk operations. Applies user decision to all
        pending confirmations in a session. Useful for "skip all duplicates"
        or "insert all" workflows.

        Args:
            session_id: Session ID
            action: User action - 'insert', 'skip', or 'merge'
            user_id: User identifier

        Returns:
            Count of confirmations processed

        Raises:
            ValueError: If action is invalid

        Examples:
            >>> repo = DuplicateConfirmationRepository(conn)
            >>> # Skip all duplicates in session
            >>> count = repo.bulk_confirm_session(
            ...     session_id=1,
            ...     action='skip',
            ...     user_id='user@example.com'
            ... )
            >>> print(f'Skipped {count} duplicates')

        Notes:
            - Only processes status='pending' confirmations
            - Uses apply_user_decision() for each confirmation
            - All operations in single transaction
            - Rolls back on any error
            - Use with caution for 'insert' action (could create many transactions)
        """
        # Validate action
        valid_actions = ('insert', 'skip', 'merge')
        if action not in valid_actions:
            raise ValueError(
                f"Invalid action: {action}. Must be one of {valid_actions}"
            )

        try:
            # Get all pending confirmations for session
            cursor = self.conn.execute('''
                SELECT id FROM duplicate_transaction_confirmations
                WHERE session_id = ? AND status = 'pending'
                ORDER BY new_transaction_index ASC
            ''', (session_id,))

            confirmation_ids = [row['id'] for row in cursor.fetchall()]

            if not confirmation_ids:
                self.logger.debug(
                    f'No pending confirmations found for session_id={session_id}'
                )
                return 0

            # Apply decision to each confirmation
            count = 0
            for conf_id in confirmation_ids:
                self.apply_user_decision(conf_id, action, user_id)
                count += 1

            self.logger.info(
                f'Bulk confirmed {count} transactions for session_id={session_id}: '
                f'action={action}, user_id={user_id}'
            )

            return count

        except Exception as e:
            self.logger.error(
                f'Error in bulk confirm for session_id={session_id}: {e}'
            )
            raise


class ProcessedFileRepository:
    """
    Repository for processed file tracking with duplicate detection.

    Manages file processing history to prevent duplicate file processing.
    Uses SHA256 file hashing for reliable duplicate detection across
    filenames and modifications.

    Attributes:
        conn: SQLite database connection
        logger: Logger instance for operations tracking

    Examples:
        >>> repo = ProcessedFileRepository(conn)
        >>> existing = repo.is_file_processed('abc123...')
        >>> if not existing:
        ...     file_id = repo.insert_file('statement.xls', '/path', 'abc123...', 1024, 1)
        ...     print(f'Processed file {file_id}')
    """

    def __init__(self, connection: sqlite3.Connection):
        """
        Initialize repository with database connection.

        Args:
            connection: SQLite database connection instance
        """
        self.conn = connection
        self.logger = logging.getLogger(__name__)
        self.logger.debug('ProcessedFileRepository initialized')

    def is_file_processed(self, file_hash: str) -> Optional[dict]:
        """
        Check if file with given hash has been processed before.

        Fast duplicate detection using indexed hash lookup. Returns full
        file record if duplicate found, None otherwise.

        Args:
            file_hash: SHA256 hash of file contents (hexdigest string)

        Returns:
            Dict with file record if processed before, None if new file

        Examples:
            >>> repo = ProcessedFileRepository(conn)
            >>> existing = repo.is_file_processed('abc123...')
            >>> if existing:
            ...     print(f"Duplicate of file processed at {existing['processed_at']}")
            ... else:
            ...     print("New file, proceed with processing")

        Notes:
            - Uses UNIQUE index on file_hash for O(1) lookup
            - Returns complete file record including original filename
            - Check this BEFORE parsing file to avoid duplicate work
        """
        try:
            cursor = self.conn.execute(
                'SELECT * FROM processed_files WHERE file_hash = ? LIMIT 1',
                (file_hash,)
            )
            row = cursor.fetchone()
            if row:
                self.logger.debug(f'File hash found: {file_hash} (file_id={row["id"]})')
                return dict(row)
            return None
        except Exception as e:
            self.logger.error(f'Error checking file hash {file_hash}: {e}')
            raise

    def insert_file(self, file_name: str, file_path: str, file_hash: str,
                    file_size: int, institution_id: int, processed_at: str) -> int:
        """
        Insert new processed file record.

        Creates file tracking record for successful processing. Uses INSERT OR IGNORE
        for thread-safe duplicate handling (race condition protection).

        Args:
            file_name: Original filename (e.g., 'statement.xls')
            file_path: Full path where file was processed (e.g., '/inbox/statement.xls')
            file_hash: SHA256 hash of file contents (hexdigest)
            file_size: File size in bytes
            institution_id: Foreign key to financial_institutions table
            processed_at: Timestamp when processing occurred (ISO format)

        Returns:
            int: File ID (lastrowid) or existing file_id if duplicate

        Examples:
            >>> from datetime import datetime
            >>> repo = ProcessedFileRepository(conn)
            >>> file_id = repo.insert_file(
            ...     'hana_statement.xls',
            ...     '/inbox/hana_statement.xls',
            ...     'abc123...',
            ...     1024,
            ...     1,
            ...     datetime.now().isoformat()
            ... )
            >>> print(f'File tracked with ID: {file_id}')

        Notes:
            - Uses INSERT OR IGNORE for hash uniqueness enforcement
            - Returns lastrowid for new inserts
            - If hash collision (duplicate), fetches existing file_id
            - archive_path initially NULL, updated later via update_archive_path()
        """
        try:
            cursor = self.conn.execute('''
                INSERT OR IGNORE INTO processed_files (
                    file_name,
                    file_path,
                    file_hash,
                    file_size,
                    institution_id,
                    processed_at
                ) VALUES (?, ?, ?, ?, ?, ?)
            ''', (file_name, file_path, file_hash, file_size, institution_id, processed_at))

            self.conn.commit()

            # If insert succeeded, use lastrowid
            if cursor.lastrowid > 0:
                self.logger.debug(
                    f'Inserted file record: {file_name} (id={cursor.lastrowid}, hash={file_hash[:16]}...)'
                )
                return cursor.lastrowid

            # If INSERT OR IGNORE did nothing, fetch existing ID
            cursor = self.conn.execute(
                'SELECT id FROM processed_files WHERE file_hash = ?',
                (file_hash,)
            )
            row = cursor.fetchone()
            if row:
                self.logger.debug(f'File hash already exists: {file_hash[:16]}... (id={row["id"]})')
                return row['id']

            raise ValueError(f'Failed to insert or retrieve file record for hash: {file_hash}')

        except Exception as e:
            self.logger.error(f'Error inserting file record for {file_name}: {e}')
            raise

    def update_archive_path(self, file_id: int, archive_path: str):
        """
        Update archive path for processed file.

        Called after file is successfully moved to archive directory.
        Records final location for audit trail and potential file recovery.

        Args:
            file_id: File ID from insert_file()
            archive_path: Path where file was archived (e.g., '/archive/statement_123.xls')

        Examples:
            >>> repo = ProcessedFileRepository(conn)
            >>> repo.update_archive_path(1, '/archive/hana_statement.xls')

        Notes:
            - Called after successful archiving
            - Commits immediately (separate transaction from insert)
            - Useful for audit trail and duplicate file management
        """
        try:
            self.conn.execute(
                'UPDATE processed_files SET archive_path = ? WHERE id = ?',
                (archive_path, file_id)
            )
            self.conn.commit()
            self.logger.debug(f'Updated archive path for file_id={file_id}: {archive_path}')
        except Exception as e:
            self.logger.error(f'Error updating archive path for file_id={file_id}: {e}')
            raise

    def get_by_id(self, file_id: int) -> Optional[dict]:
        """
        Get processed file record by ID.

        Useful for audit queries and debugging file processing history.

        Args:
            file_id: File ID

        Returns:
            Dict with file record or None if not found

        Examples:
            >>> repo = ProcessedFileRepository(conn)
            >>> file_record = repo.get_by_id(1)
            >>> if file_record:
            ...     print(f"File: {file_record['file_name']}")
            ...     print(f"Processed: {file_record['processed_at']}")

        Notes:
            - Returns all fields including hash, size, institution_id
            - Useful for investigating duplicate detection
        """
        try:
            cursor = self.conn.execute(
                'SELECT * FROM processed_files WHERE id = ?',
                (file_id,)
            )
            row = cursor.fetchone()
            return dict(row) if row else None
        except Exception as e:
            self.logger.error(f'Error fetching file record {file_id}: {e}')
            raise
