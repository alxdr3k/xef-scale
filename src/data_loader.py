"""
DataLoader for database persistence and file archiving.
Handles saving transactions to SQLite database and archiving processed files.
"""

import shutil
import os
import time
import sqlite3
from typing import List
from src.models import Transaction
from src.config import DIRECTORIES
from src.db.connection import DatabaseConnection
from src.db.repository import CategoryRepository, InstitutionRepository, TransactionRepository
import logging


class DataLoader:
    """
    Manages data persistence and file archiving for expense tracking system.

    Saves transactions to SQLite database using repository pattern
    and archives processed statement files to prevent reprocessing.

    Attributes:
        ledger_path: Path to master_ledger.csv file (kept for backward compatibility)
        archive_dir: Path to archive directory for processed files
        conn: Database connection instance
        category_repo: Repository for category operations
        institution_repo: Repository for institution operations
        transaction_repo: Repository for transaction operations
        logger: Logger instance for tracking operations
    """

    def __init__(self):
        """
        Initialize DataLoader with database repositories.

        Sets up database connection and initializes all repository instances
        for transaction persistence. Repositories are cached to reuse their
        in-memory lookups across multiple save operations.
        """
        self.ledger_path = os.path.join(DIRECTORIES['data'], 'master_ledger.csv')
        self.archive_dir = DIRECTORIES['archive']
        self.logger = logging.getLogger(__name__)

        # Initialize database repositories
        self.conn = DatabaseConnection.get_instance()
        self.category_repo = CategoryRepository(self.conn)
        self.institution_repo = InstitutionRepository(self.conn)
        self.transaction_repo = TransactionRepository(
            self.conn,
            self.category_repo,
            self.institution_repo
        )
        self.logger.debug('Database repositories initialized')

    def save(self, transactions: List[Transaction]):
        """
        Save transactions to SQLite database with retry logic.

        Inserts transactions using batch_insert for performance. Handles
        database lock errors with exponential backoff retry strategy.

        Args:
            transactions: List of Transaction objects to save

        Examples:
            >>> loader = DataLoader()
            >>> transactions = [Transaction(...), Transaction(...)]
            >>> loader.save(transactions)

        Notes:
            - Empty transaction lists are ignored
            - Duplicates are automatically handled by UNIQUE constraint
            - Retries up to 3 times on database lock errors
            - Uses exponential backoff: 0.5s, 1s, 2s delays

        Raises:
            sqlite3.OperationalError: If database remains locked after retries
            Exception: For other database errors
        """
        if not transactions:
            self.logger.info('No transactions to save')
            return

        # Retry logic for database lock handling
        max_attempts = 3
        backoff_delays = [0.5, 1.0, 2.0]

        for attempt in range(max_attempts):
            try:
                # Attempt batch insert
                count = self.transaction_repo.batch_insert(transactions)
                self.logger.info(f'Saved {count} transactions to database')
                return  # Success - exit function

            except sqlite3.OperationalError as e:
                error_msg = str(e).lower()

                # Check if it's a database lock error
                if 'database is locked' in error_msg and attempt < max_attempts - 1:
                    delay = backoff_delays[attempt]
                    self.logger.warning(
                        f'Database locked, retrying in {delay}s '
                        f'(attempt {attempt + 1}/{max_attempts})'
                    )
                    time.sleep(delay)
                else:
                    # Either not a lock error or out of retries
                    self.logger.error(
                        f'Failed to save transactions after {max_attempts} attempts: {e}'
                    )
                    raise

            except Exception as e:
                self.logger.error(f'Error saving transactions: {e}')
                raise

    def archive_file(self, source_path: str):
        """
        Move processed file to archive directory.

        Handles duplicate filenames by appending timestamp.
        Prevents reprocessing of already-handled statement files.

        Args:
            source_path: Path to the file to archive

        Examples:
            >>> loader = DataLoader()
            >>> loader.archive_file('inbox/statement.xlsx')

        Notes:
            - If destination file exists, adds timestamp to avoid overwrite
            - Uses shutil.move for efficient file relocation
            - Logs all archive operations

        Raises:
            FileNotFoundError: If source file doesn't exist
            PermissionError: If insufficient permissions
        """
        filename = os.path.basename(source_path)
        dest_path = os.path.join(self.archive_dir, filename)

        # Handle duplicate filenames by appending timestamp
        if os.path.exists(dest_path):
            base, ext = os.path.splitext(filename)
            timestamp = int(time.time())
            dest_path = os.path.join(self.archive_dir, f'{base}_{timestamp}{ext}')
            self.logger.info(f'Duplicate filename detected, using timestamp: {os.path.basename(dest_path)}')

        # Move file to archive
        shutil.move(source_path, dest_path)
        self.logger.info(f'Archived file: {filename} -> {os.path.basename(dest_path)}')
