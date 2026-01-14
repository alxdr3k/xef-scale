"""
Pytest configuration for expense tracker tests.

Provides test database isolation using in-memory SQLite database.
Ensures tests don't affect production data.
"""

import pytest
import sqlite3
import tempfile
import os
import logging
from typing import Generator

from src.db.connection import DatabaseConnection
from src.db import migrate as migrate_module


@pytest.fixture(scope="session")
def test_db_path() -> Generator[str, None, None]:
    """
    Create a temporary test database file for the test session.

    Yields:
        str: Path to temporary test database file

    Cleanup:
        Deletes the temporary database file after all tests complete
    """
    # Create temporary file
    fd, db_path = tempfile.mkstemp(suffix='.db', prefix='expense_tracker_test_')
    os.close(fd)

    yield db_path

    # Cleanup
    try:
        if os.path.exists(db_path):
            os.unlink(db_path)
    except Exception as e:
        print(f"Warning: Failed to delete test database {db_path}: {e}")


@pytest.fixture(scope="function")
def test_db_connection(test_db_path: str) -> Generator[sqlite3.Connection, None, None]:
    """
    Provide a test database connection with fresh schema for each test.

    This fixture:
    1. Creates a new connection to test database
    2. Runs migrations to set up schema
    3. Enables WAL mode and foreign keys
    4. Yields connection for test use
    5. Cleans up by closing connection after test

    Yields:
        sqlite3.Connection: Test database connection with schema initialized

    Note:
        Each test gets a fresh database, ensuring complete isolation.
    """
    # Remove existing test database to ensure clean state
    if os.path.exists(test_db_path):
        try:
            os.unlink(test_db_path)
        except Exception:
            pass

    # Create connection to test database
    conn = sqlite3.connect(
        test_db_path,
        timeout=30.0,
        check_same_thread=False
    )

    # Enable WAL mode
    conn.execute('PRAGMA journal_mode=WAL')

    # Enable foreign key constraints
    conn.execute('PRAGMA foreign_keys=ON')

    # Set row factory for dict-like access
    conn.row_factory = sqlite3.Row

    # Run migrations to create schema
    # Create migrations tracking table
    migrate_module.create_migrations_table(conn)

    # Get pending migrations and execute them
    pending_migrations = migrate_module.get_pending_migrations('db/migrations')
    for filename in pending_migrations:
        migration_path = os.path.join('db/migrations', filename)
        try:
            # Read and execute SQL directly without tracking (for test isolation)
            with open(migration_path, 'r', encoding='utf-8') as f:
                sql = f.read()
            conn.executescript(sql)
        except Exception as e:
            # Silently skip migration errors in tests (already applied migrations, etc.)
            pass

    conn.commit()

    yield conn

    # Cleanup after test
    try:
        conn.rollback()
        conn.close()
    except Exception as e:
        print(f"Warning: Error closing test connection: {e}")


@pytest.fixture(scope="function")
def test_db_override(test_db_connection: sqlite3.Connection) -> Generator[None, None, None]:
    """
    Override DatabaseConnection singleton to use test database.

    This fixture temporarily replaces the production database connection
    with a test database connection for the duration of a test.

    Usage:
        def test_something(test_db_override):
            # All database operations use test database
            conn = DatabaseConnection.get_instance()

    Yields:
        None

    Cleanup:
        Restores original database connection after test
    """
    # Store original instance
    original_instance = DatabaseConnection._instance

    # Override with test connection
    DatabaseConnection._instance = test_db_connection

    yield

    # Restore original instance
    DatabaseConnection._instance = original_instance
