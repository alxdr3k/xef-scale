"""
FileProcessor for file-based deduplication and transaction extraction.
Implements SHA256 hashing for duplicate detection and orchestrates the
complete file processing workflow with file tracking.
"""

import hashlib
import os
import shutil
import logging
from pathlib import Path
from datetime import datetime
from typing import Optional

from src.config import DIRECTORIES
from src.models import ProcessingResult
from src.db.connection import DatabaseConnection
from src.db.repository import (
    CategoryRepository,
    InstitutionRepository,
    TransactionRepository,
    ProcessedFileRepository
)
from src.router import StatementRouter
from src.parsers.hana_parser import HanaCardParser


def calculate_file_hash(file_path: Path) -> str:
    """
    Calculate SHA256 hash of file contents.

    Reads file in 8KB chunks to handle large files efficiently.
    Hash is computed on file contents, not filename or metadata.

    Args:
        file_path: Path to file

    Returns:
        str: SHA256 hash as hexdigest string

    Examples:
        >>> from pathlib import Path
        >>> hash1 = calculate_file_hash(Path('inbox/statement.xls'))
        >>> hash2 = calculate_file_hash(Path('inbox/statement.xls'))
        >>> assert hash1 == hash2  # Same file, same hash

        >>> # Different filename, same contents
        >>> shutil.copy('inbox/statement.xls', 'inbox/copy.xls')
        >>> hash3 = calculate_file_hash(Path('inbox/copy.xls'))
        >>> assert hash1 == hash3  # Duplicate detected!

    Notes:
        - Uses 8KB chunk size for memory efficiency
        - Content-based hashing ignores filename changes
        - Detects byte-identical duplicates reliably
        - Fast: O(n) where n = file size
    """
    sha256_hash = hashlib.sha256()

    with open(file_path, 'rb') as f:
        # Read file in 8KB chunks
        for chunk in iter(lambda: f.read(8192), b''):
            sha256_hash.update(chunk)

    return sha256_hash.hexdigest()


class FileProcessor:
    """
    Processes financial statement files with deduplication and transaction extraction.

    Orchestrates complete file processing workflow:
    1. Calculate file hash for duplicate detection
    2. Check if file already processed (skip if duplicate)
    3. Identify institution via router
    4. Parse transactions using institution-specific parser
    5. Save transactions with file tracking
    6. Archive processed file
    7. Update file record with archive path

    Attributes:
        conn: Database connection instance
        category_repo: Repository for category lookups
        institution_repo: Repository for institution lookups
        transaction_repo: Repository for transaction operations
        processed_file_repo: Repository for file tracking
        router: StatementRouter for institution identification
        parsers: Dict mapping institution codes to parser instances
        logger: Logger instance for operations tracking

    Examples:
        >>> processor = FileProcessor()
        >>> result = processor.process_file(Path('inbox/hana_statement.xls'))
        >>> if result.is_success():
        ...     print(f"Processed {result.transaction_count} transactions")
        ... elif result.is_duplicate():
        ...     print(f"Duplicate file skipped: {result.file_hash}")
        ... else:
        ...     print(f"Error: {result.message}")
    """

    def __init__(self):
        """
        Initialize FileProcessor with database repositories and parsers.

        Sets up all dependencies for file processing workflow.
        Creates archive/duplicates/ directory if needed.
        """
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
        self.processed_file_repo = ProcessedFileRepository(self.conn)
        self.logger.debug('Database repositories initialized')

        # Initialize router and parsers
        self.router = StatementRouter()
        self.parsers = {
            'HANA': HanaCardParser()
            # Future: Add more parsers (TOSS, KAKAO, SHINHAN)
        }
        self.logger.debug(f'Parsers initialized: {list(self.parsers.keys())}')

        # Ensure duplicates directory exists
        duplicates_dir = os.path.join(DIRECTORIES['archive'], 'duplicates')
        os.makedirs(duplicates_dir, exist_ok=True)
        self.logger.debug(f'Duplicates directory: {duplicates_dir}')

    def process_file(self, file_path: Path) -> ProcessingResult:
        """
        Process financial statement file with deduplication.

        Complete workflow with error handling and comprehensive logging.
        Returns ProcessingResult for structured status communication.

        Args:
            file_path: Path to statement file to process

        Returns:
            ProcessingResult with status ('success', 'duplicate', 'error'),
            message, transaction_count, file_id, and file_hash

        Examples:
            >>> processor = FileProcessor()
            >>> result = processor.process_file(Path('inbox/statement.xls'))
            >>> if result.is_success():
            ...     print(f"File ID: {result.file_id}")
            ...     print(f"Transactions: {result.transaction_count}")
            ...     print(f"Hash: {result.file_hash[:16]}...")

        Notes:
            - Duplicate files moved to archive/duplicates/
            - New files archived to archive/ after processing
            - Transaction count excludes duplicates (INSERT OR IGNORE)
            - All errors caught and returned as ProcessingResult
        """
        file_path = Path(file_path)  # Ensure Path object
        filename = file_path.name
        self.logger.info(f'Processing file: {filename}')

        try:
            # Step 1: Calculate file hash
            file_hash = calculate_file_hash(file_path)
            file_size = file_path.stat().st_size
            self.logger.debug(f'File hash: {file_hash[:16]}... (size: {file_size} bytes)')

            # Step 2: Check for duplicates
            existing_file = self.processed_file_repo.is_file_processed(file_hash)
            if existing_file:
                self.logger.warning(
                    f'Duplicate file detected: {filename} '
                    f'(original: {existing_file["file_name"]}, '
                    f'processed: {existing_file["processed_at"]})'
                )

                # Move duplicate to archive/duplicates/
                duplicates_dir = os.path.join(DIRECTORIES['archive'], 'duplicates')
                dest_path = os.path.join(duplicates_dir, filename)

                # Handle duplicate filename in duplicates directory
                if os.path.exists(dest_path):
                    base, ext = os.path.splitext(filename)
                    timestamp = int(datetime.now().timestamp())
                    dest_path = os.path.join(duplicates_dir, f'{base}_{timestamp}{ext}')

                shutil.move(str(file_path), dest_path)
                self.logger.info(f'Moved duplicate file to: {dest_path}')

                return ProcessingResult(
                    status='duplicate',
                    message=f'Duplicate of {existing_file["file_name"]} processed on {existing_file["processed_at"]}',
                    transaction_count=0,
                    file_id=None,
                    file_hash=file_hash
                )

            # Step 3: Identify institution
            institution = self.router.identify(str(file_path))
            if not institution:
                self.logger.warning(f'Could not identify institution for: {filename}')
                return ProcessingResult(
                    status='error',
                    message='Could not identify financial institution',
                    transaction_count=0,
                    file_id=None,
                    file_hash=file_hash
                )

            if institution not in self.parsers:
                self.logger.warning(f'No parser available for {institution}: {filename}')
                return ProcessingResult(
                    status='error',
                    message=f'No parser available for institution: {institution}',
                    transaction_count=0,
                    file_id=None,
                    file_hash=file_hash
                )

            self.logger.info(f'Identified as {institution} statement')

            # Step 4: Parse transactions
            parser = self.parsers[institution]
            transactions = parser.parse(str(file_path))

            if not transactions:
                self.logger.warning(f'No transactions extracted from: {filename}')
                return ProcessingResult(
                    status='error',
                    message='No transactions found in file',
                    transaction_count=0,
                    file_id=None,
                    file_hash=file_hash
                )

            self.logger.info(f'Extracted {len(transactions)} transactions')

            # Step 5: Insert file record
            institution_id = self.institution_repo.get_or_create(transactions[0].source)
            processed_at = datetime.now().isoformat()

            file_id = self.processed_file_repo.insert_file(
                file_name=filename,
                file_path=str(file_path.absolute()),
                file_hash=file_hash,
                file_size=file_size,
                institution_id=institution_id,
                processed_at=processed_at
            )
            self.logger.info(f'Created file record: file_id={file_id}')

            # Step 6: Save transactions with file_id
            count = self.transaction_repo.batch_insert(transactions, file_id=file_id)
            self.logger.info(f'Saved {count} transactions to database')

            # Step 7: Archive file
            archive_dir = DIRECTORIES['archive']
            dest_path = os.path.join(archive_dir, filename)

            # Handle duplicate filename in archive
            if os.path.exists(dest_path):
                base, ext = os.path.splitext(filename)
                timestamp = int(datetime.now().timestamp())
                dest_path = os.path.join(archive_dir, f'{base}_{timestamp}{ext}')

            shutil.move(str(file_path), dest_path)
            self.logger.info(f'Archived file to: {dest_path}')

            # Step 8: Update file record with archive path
            self.processed_file_repo.update_archive_path(file_id, dest_path)

            return ProcessingResult(
                status='success',
                message=f'Successfully processed {count} transactions from {filename}',
                transaction_count=count,
                file_id=file_id,
                file_hash=file_hash
            )

        except FileNotFoundError:
            self.logger.error(f'File not found: {filename}')
            return ProcessingResult(
                status='error',
                message=f'File not found: {filename}',
                transaction_count=0,
                file_id=None,
                file_hash=None
            )

        except Exception as e:
            self.logger.error(f'Error processing {filename}: {e}', exc_info=True)
            return ProcessingResult(
                status='error',
                message=f'Processing failed: {str(e)}',
                transaction_count=0,
                file_id=None,
                file_hash=None
            )
