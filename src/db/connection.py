"""
Database connection manager using singleton pattern.
Provides thread-safe access to SQLite database with optimized settings.
"""

import sqlite3
import threading
import os
import logging
from src.config import DIRECTORIES


class DatabaseConnection:
    """
    Singleton database connection manager for SQLite.

    Provides a single, thread-safe connection to the expense tracker database
    with optimized settings: WAL mode for concurrent access, foreign key
    constraints enabled, and dict-like row access.

    Attributes:
        _instance: Class-level singleton connection instance
        _lock: Threading lock for thread-safe singleton initialization

    Examples:
        >>> conn = DatabaseConnection.get_instance()
        >>> cursor = conn.execute('SELECT * FROM categories')
        >>> row = cursor.fetchone()
        >>> print(row['name'])  # Dict-like access
        '식비'
    """

    _instance = None
    _lock = threading.Lock()

    def __init__(self):
        """
        Private constructor to prevent direct instantiation.

        Raises:
            RuntimeError: Always raises to enforce singleton pattern
        """
        raise RuntimeError('Use get_instance() instead of direct instantiation')

    @classmethod
    def get_instance(cls) -> sqlite3.Connection:
        """
        Get the singleton database connection instance.

        Creates a new connection on first call, returns existing connection
        on subsequent calls. Thread-safe using double-check locking pattern.

        Returns:
            sqlite3.Connection: Configured database connection with:
                - WAL mode enabled for concurrent reads
                - Foreign key constraints enforced
                - Row factory for dict-like access
                - 30-second timeout for lock handling

        Examples:
            >>> conn1 = DatabaseConnection.get_instance()
            >>> conn2 = DatabaseConnection.get_instance()
            >>> assert conn1 is conn2  # Same instance

        Notes:
            - First call creates connection and applies PRAGMA settings
            - Subsequent calls return cached connection (no overhead)
            - Thread-safe for use in multi-threaded file watcher context
        """
        logger = logging.getLogger(__name__)

        # Fast path: return existing instance without lock
        if cls._instance is not None:
            return cls._instance

        # Slow path: create new instance with double-check locking
        with cls._lock:
            # Check again inside lock (another thread may have created it)
            if cls._instance is None:
                db_path = os.path.join(DIRECTORIES['data'], 'expense_tracker.db')
                logger.info(f'Initializing database connection: {db_path}')

                # Create connection with optimized settings
                conn = sqlite3.connect(
                    db_path,
                    timeout=30.0,  # 30-second timeout for lock handling
                    check_same_thread=False  # Allow use across threads
                )

                # Enable WAL mode for concurrent reads
                conn.execute('PRAGMA journal_mode=WAL')
                logger.debug('WAL mode enabled')

                # Enable foreign key constraints
                conn.execute('PRAGMA foreign_keys=ON')
                logger.debug('Foreign key constraints enabled')

                # Set row factory for dict-like access
                conn.row_factory = sqlite3.Row

                cls._instance = conn
                logger.info('Database connection initialized successfully')

        return cls._instance

    @classmethod
    def close(cls):
        """
        Close the database connection and reset singleton.

        Useful for testing or graceful shutdown. After calling close(),
        the next call to get_instance() will create a new connection.

        Examples:
            >>> DatabaseConnection.close()
            >>> conn = DatabaseConnection.get_instance()  # New connection

        Notes:
            - Thread-safe operation
            - Commits any pending transactions before closing
            - Silently ignores if no connection exists
        """
        logger = logging.getLogger(__name__)

        with cls._lock:
            if cls._instance is not None:
                try:
                    cls._instance.commit()
                    cls._instance.close()
                    logger.info('Database connection closed')
                except Exception as e:
                    logger.warning(f'Error closing database connection: {e}')
                finally:
                    cls._instance = None
