"""
FileProcessor for file-based deduplication and transaction extraction.
Implements SHA256 hashing for duplicate detection and orchestrates the
complete file processing workflow with file tracking.
"""

import hashlib
import os
import shutil
import logging
import json
from pathlib import Path
from datetime import datetime
from typing import Optional

from src.config import DIRECTORIES
from src.models import ProcessingResult, ParseResult
from src.db.connection import DatabaseConnection
from src.db.repository import (
    CategoryRepository,
    InstitutionRepository,
    TransactionRepository,
    ProcessedFileRepository,
    ParsingSessionRepository,
    SkippedTransactionRepository
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
        self.parsing_session_repo = ParsingSessionRepository(self.conn)
        self.skipped_transaction_repo = SkippedTransactionRepository(self.conn)
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

    def _validate_session(self, parse_result: ParseResult,
                         saved_count: int, duplicate_count: int) -> tuple:
        """
        Validate parsing session completeness.

        Compares expected rows vs actual (saved + skipped + duplicate).

        Args:
            parse_result: ParseResult from parser
            saved_count: Count returned from batch_insert (excludes duplicates)
            duplicate_count: Number of transactions that were duplicates

        Returns:
            Tuple of (validation_status, validation_notes)
            - status: 'pass', 'warning', or 'fail'
            - notes: Human-readable summary
        """
        total_scanned = parse_result.total_rows_scanned
        success_count = parse_result.success_count()
        skip_count = parse_result.skip_count()

        # Expected: scanned = success + skipped
        # Actual: saved + duplicate + skipped
        actual_accounted = saved_count + duplicate_count + skip_count

        if actual_accounted == total_scanned:
            # Perfect: All rows accounted for
            return ('pass', f'All {total_scanned} rows accounted for: '
                           f'{saved_count} saved, {duplicate_count} duplicate, '
                           f'{skip_count} skipped')

        elif actual_accounted < total_scanned:
            # Warning: Some rows missing
            missing = total_scanned - actual_accounted
            return ('warning', f'Missing {missing} rows: scanned {total_scanned}, '
                              f'accounted {actual_accounted} '
                              f'(saved={saved_count}, dup={duplicate_count}, skip={skip_count})')

        else:
            # Fail: More rows accounted than scanned (logic error)
            extra = actual_accounted - total_scanned
            return ('fail', f'Accounting error: {extra} extra rows reported. '
                           f'Scanned {total_scanned}, accounted {actual_accounted}')

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

            # Variables for error handling
            session_id = None

            try:
                # Step 4: Parse transactions (UPDATED)
                parser = self.parsers[institution]
                parse_result = parser.parse(str(file_path))

                # Backward compatibility check
                if isinstance(parse_result, list):
                    # Old parser returning List[Transaction]
                    parse_result = ParseResult(
                        transactions=parse_result,
                        skipped=[],
                        total_rows_scanned=len(parse_result),
                        parser_type=institution
                    )

                if not parse_result.transactions:
                    self.logger.warning(f'No transactions extracted from: {filename}')
                    return ProcessingResult(
                        status='error',
                        message='No transactions found in file',
                        transaction_count=0,
                        file_id=None,
                        file_hash=file_hash
                    )

                self.logger.info(
                    f'Parse complete: {parse_result.success_count()} transactions, '
                    f'{parse_result.skip_count()} skipped'
                )

                # Step 5: Insert file record
                institution_id = self.institution_repo.get_or_create(parse_result.transactions[0].source)
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

                # Step 6: Create parsing session (NEW)
                session_id = self.parsing_session_repo.create_session(
                    file_id=file_id,
                    parser_type=parse_result.parser_type,
                    total_rows=parse_result.total_rows_scanned
                )
                self.logger.debug(f'Created parsing session: {session_id}')

                # Step 7: Check for duplicate transactions and handle accordingly
                from src.duplicate_detector import DuplicateDetector
                from src.db.repository import DuplicateConfirmationRepository

                try:
                    # Step 7a: Initialize duplicate detector
                    duplicate_detector = DuplicateDetector(self.transaction_repo)
                    self.logger.debug('Checking for duplicate transactions')

                    # Step 7b: Check for duplicates
                    duplicate_matches = duplicate_detector.check_for_duplicates(
                        parse_result.transactions,
                        file_id=file_id
                    )

                    if duplicate_matches:
                        # Step 7c: Create confirmation records for duplicates
                        self.logger.info(f'Found {len(duplicate_matches)} potential duplicate transactions')
                        confirmation_repo = DuplicateConfirmationRepository(self.conn)

                        for match in duplicate_matches:
                            confirmation_repo.create_confirmation(
                                session_id=session_id,
                                new_transaction_data=json.dumps(match.new_transaction.to_dict()),
                                new_transaction_index=match.new_transaction_index,
                                existing_transaction_id=match.existing_transaction_id,
                                confidence_score=match.confidence_score,
                                match_fields=json.dumps(match.match_fields),
                                difference_summary=match.difference_summary
                            )

                        # Step 7d: Mark session as pending confirmation
                        self.parsing_session_repo.update_status(
                            session_id=session_id,
                            status='pending_confirmation'
                        )
                        self.logger.info(f'Session {session_id} marked as pending_confirmation')

                        # Step 7e: Insert only non-duplicate transactions
                        duplicate_indices = {match.new_transaction_index for match in duplicate_matches}
                        non_duplicate_transactions = [
                            t for i, t in enumerate(parse_result.transactions, start=1)
                            if i not in duplicate_indices
                        ]

                        count = 0
                        if non_duplicate_transactions:
                            count = self.transaction_repo.batch_insert(
                                non_duplicate_transactions,
                                file_id=file_id
                            )
                            self.logger.info(f'Saved {count} non-duplicate transactions to database')

                        # Step 7f: Update session with partial results
                        self.parsing_session_repo.update_processing_result(
                            session_id=session_id,
                            rows_saved=count,
                            rows_pending=len(duplicate_matches)
                        )

                        # Step 7g: Archive file (same as normal flow)
                        archive_dir = DIRECTORIES['archive']
                        dest_path = os.path.join(archive_dir, filename)

                        if os.path.exists(dest_path):
                            base, ext = os.path.splitext(filename)
                            timestamp = int(datetime.now().timestamp())
                            dest_path = os.path.join(archive_dir, f'{base}_{timestamp}{ext}')

                        shutil.move(str(file_path), dest_path)
                        self.logger.info(f'Archived file to: {dest_path}')

                        # Step 7h: Update file record with archive path
                        self.processed_file_repo.update_archive_path(file_id, dest_path)

                        # Step 7i: Return pending confirmation result
                        return ProcessingResult(
                            status='pending_confirmation',
                            message=f'{len(duplicate_matches)} potential duplicates detected. {count} unique transactions inserted.',
                            transaction_count=count,
                            transactions_pending=len(duplicate_matches),
                            session_id=session_id,
                            file_id=file_id,
                            file_hash=file_hash
                        )

                    else:
                        # No duplicates detected - proceed with normal flow
                        self.logger.debug('No duplicate transactions detected')

                except Exception as e:
                    # If duplicate detection fails, log error but continue with normal flow
                    self.logger.error(f'Duplicate detection failed: {e}', exc_info=True)
                    self.logger.warning('Continuing with normal insertion flow despite duplicate detection error')

                # Step 7j: Save all transactions (normal flow when no duplicates or detection failed)
                count = self.transaction_repo.batch_insert(
                    parse_result.transactions,
                    file_id=file_id
                )
                self.logger.info(f'Saved {count} transactions to database')

                # Step 8: Save skipped transactions (NEW)
                skipped_count = self.skipped_transaction_repo.batch_insert(
                    session_id,
                    parse_result.skipped
                )
                self.logger.info(f'Saved {skipped_count} skipped transaction records')

                # Step 9: Calculate duplicate count (NEW)
                duplicate_count = len(parse_result.transactions) - count

                # Step 10: Run validation (NEW)
                validation_status, validation_notes = self._validate_session(
                    parse_result, count, duplicate_count
                )

                # Step 11: Complete session with validation results (NEW)
                self.parsing_session_repo.complete_session(
                    session_id=session_id,
                    rows_saved=count,
                    rows_skipped=parse_result.skip_count(),
                    rows_duplicate=duplicate_count,
                    validation_status=validation_status,
                    validation_notes=validation_notes
                )
                self.logger.info(f'Completed parsing session {session_id}: {validation_status}')

                # Step 12: Archive file
                archive_dir = DIRECTORIES['archive']
                dest_path = os.path.join(archive_dir, filename)

                # Handle duplicate filename in archive
                if os.path.exists(dest_path):
                    base, ext = os.path.splitext(filename)
                    timestamp = int(datetime.now().timestamp())
                    dest_path = os.path.join(archive_dir, f'{base}_{timestamp}{ext}')

                shutil.move(str(file_path), dest_path)
                self.logger.info(f'Archived file to: {dest_path}')

                # Step 13: Update file record with archive path
                self.processed_file_repo.update_archive_path(file_id, dest_path)

                return ProcessingResult(
                    status='success',
                    message=f'Successfully processed {count} transactions from {filename}',
                    transaction_count=count,
                    file_id=file_id,
                    file_hash=file_hash
                )

            except Exception as e:
                # Mark session as failed if it was created
                if session_id is not None:
                    self.parsing_session_repo.fail_session(session_id, str(e))
                    self.logger.error(f'Marked session {session_id} as failed')
                raise  # Re-raise to be caught by outer exception handler

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

    def cleanup_old_archives(self) -> dict:
        """
        Automatically delete archived files older than retention period.

        Removes files from archive directory that exceed ARCHIVE_RETENTION_DAYS.
        This prevents unlimited disk usage from accumulated archived files.

        Returns:
            dict: Cleanup statistics with deleted_count, errors, and skipped_count

        Examples:
            >>> processor = FileProcessor()
            >>> result = processor.cleanup_old_archives()
            >>> print(f"Deleted {result['deleted_count']} old files")

        Notes:
            - Controlled by ARCHIVE_CLEANUP_ENABLED config
            - Default retention: 30 days (configurable via ARCHIVE_RETENTION_DAYS)
            - Skips subdirectories (only cleans files in root archive/)
            - Safe: Does not touch DB records, only physical files
            - Run automatically after each file processing
        """
        from src.config import ARCHIVE_RETENTION_DAYS, ARCHIVE_CLEANUP_ENABLED
        from datetime import timedelta

        if not ARCHIVE_CLEANUP_ENABLED:
            self.logger.debug('Archive cleanup disabled in config')
            return {'deleted_count': 0, 'errors': [], 'skipped_count': 0}

        archive_path = Path(DIRECTORIES['archive'])
        if not archive_path.exists():
            self.logger.warning(f'Archive directory does not exist: {archive_path}')
            return {'deleted_count': 0, 'errors': [], 'skipped_count': 0}

        cutoff_time = datetime.now() - timedelta(days=ARCHIVE_RETENTION_DAYS)
        deleted_count = 0
        skipped_count = 0
        errors = []

        try:
            for item in archive_path.iterdir():
                try:
                    # Skip directories (like duplicates/)
                    if item.is_dir():
                        skipped_count += 1
                        continue

                    # Check file modification time
                    file_mtime = datetime.fromtimestamp(item.stat().st_mtime)

                    if file_mtime < cutoff_time:
                        # File is older than retention period, delete it
                        item.unlink()
                        deleted_count += 1
                        self.logger.info(
                            f'Deleted old archive file: {item.name} '
                            f'(age: {(datetime.now() - file_mtime).days} days)'
                        )
                    else:
                        # File is still within retention period
                        skipped_count += 1

                except Exception as e:
                    error_msg = f'Error deleting {item.name}: {str(e)}'
                    errors.append(error_msg)
                    self.logger.error(error_msg)

            if deleted_count > 0:
                self.logger.info(
                    f'Archive cleanup completed: {deleted_count} deleted, '
                    f'{skipped_count} kept, {len(errors)} errors'
                )

        except Exception as e:
            error_msg = f'Error during archive cleanup: {str(e)}'
            errors.append(error_msg)
            self.logger.error(error_msg)

        return {
            'deleted_count': deleted_count,
            'skipped_count': skipped_count,
            'errors': errors
        }
