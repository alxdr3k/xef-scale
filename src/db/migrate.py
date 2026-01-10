"""
Database migration runner CLI.
Executes SQL migrations from db/migrations/ directory with tracking.
"""

import os
import logging
from typing import Set, List
from src.db.connection import DatabaseConnection


def create_migrations_table(conn):
    """
    Create migrations tracking table if it doesn't exist.

    Tracks executed migrations by filename with timestamp to prevent
    re-execution of already-applied migrations.

    Args:
        conn: SQLite database connection

    Notes:
        - UNIQUE constraint on filename prevents duplicate tracking
        - executed_at timestamp records when migration was applied
    """
    conn.execute('''
        CREATE TABLE IF NOT EXISTS _migrations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            filename TEXT NOT NULL UNIQUE,
            executed_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    conn.commit()


def get_executed_migrations(conn) -> Set[str]:
    """
    Get set of already-executed migration filenames.

    Queries _migrations table to determine which migrations have been applied.

    Args:
        conn: SQLite database connection

    Returns:
        Set of migration filenames that have been executed

    Examples:
        >>> executed = get_executed_migrations(conn)
        >>> print(executed)
        {'001_create_schema.sql', '002_seed_initial_data.sql'}
    """
    cursor = conn.execute('SELECT filename FROM _migrations')
    return {row['filename'] for row in cursor.fetchall()}


def get_pending_migrations(migrations_dir: str) -> List[str]:
    """
    Get sorted list of SQL migration files from migrations directory.

    Scans directory for .sql files and sorts them numerically to ensure
    correct execution order (e.g., 001_, 002_, 003_).

    Args:
        migrations_dir: Path to migrations directory (e.g., 'db/migrations')

    Returns:
        Sorted list of .sql filenames

    Examples:
        >>> migrations = get_pending_migrations('db/migrations')
        >>> print(migrations)
        ['001_create_schema.sql', '002_seed_initial_data.sql']

    Notes:
        - Only .sql files are included (Python scripts are skipped)
        - Files are sorted alphabetically (works for numeric prefixes)
        - Non-existent directory returns empty list
    """
    if not os.path.exists(migrations_dir):
        return []

    files = os.listdir(migrations_dir)
    sql_files = [f for f in files if f.endswith('.sql')]
    return sorted(sql_files)


def execute_migration(conn, migration_path: str, filename: str, logger):
    """
    Execute a single migration file.

    Reads SQL file, executes via executescript() for multi-statement support,
    and records execution in _migrations table.

    Args:
        conn: SQLite database connection
        migration_path: Full path to migration file
        filename: Migration filename (for tracking)
        logger: Logger instance

    Raises:
        Exception: If migration execution fails

    Notes:
        - Uses executescript() which supports multiple SQL statements
        - Commits after successful execution
        - Records filename in _migrations table for tracking
    """
    logger.info(f'Executing migration: {filename}')

    with open(migration_path, 'r', encoding='utf-8') as f:
        sql = f.read()

    # Execute migration SQL (may contain multiple statements)
    conn.executescript(sql)

    # Record migration execution
    conn.execute('INSERT INTO _migrations (filename) VALUES (?)', (filename,))
    conn.commit()

    logger.info(f'Successfully executed: {filename}')


def main():
    """
    Main migration runner entry point.

    Creates migrations tracking table, scans for pending migrations,
    and executes them in order while skipping already-executed ones.

    Raises:
        Exception: Halts on first migration failure

    Examples:
        >>> # Run via command line
        >>> # python -m src.db.migrate

    Notes:
        - Exits with error code on migration failure
        - Logs all operations for debugging
        - Safe to run multiple times (idempotent)
    """
    logger = logging.getLogger(__name__)

    try:
        # Get database connection
        conn = DatabaseConnection.get_instance()
        logger.info('Connected to database')

        # Create migrations tracking table
        create_migrations_table(conn)
        logger.info('Migrations tracking table ready')

        # Get executed and pending migrations
        executed = get_executed_migrations(conn)
        pending = get_pending_migrations('db/migrations')

        logger.info(f'Found {len(pending)} migration files')
        logger.info(f'Already executed: {len(executed)} migrations')

        # Execute pending migrations
        executed_count = 0
        for filename in pending:
            if filename in executed:
                logger.info(f'Skipping already executed: {filename}')
                continue

            migration_path = os.path.join('db/migrations', filename)

            try:
                execute_migration(conn, migration_path, filename, logger)
                executed_count += 1
            except Exception as e:
                logger.error(f'Migration failed: {filename} - {e}')
                raise

        if executed_count == 0:
            logger.info('No new migrations to execute')
        else:
            logger.info(f'Successfully executed {executed_count} new migrations')

    except Exception as e:
        logger.error(f'Migration runner failed: {e}')
        raise


if __name__ == '__main__':
    # Configure logging to match main.py style
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        handlers=[
            logging.StreamHandler()
        ]
    )

    main()
