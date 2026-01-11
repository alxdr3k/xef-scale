"""
FileWatcher for monitoring inbox directory and processing statement files.
Uses watchdog library to detect new files and orchestrate the parsing workflow.
"""

import time
import os
import shutil
from pathlib import Path
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
from src.file_processor import FileProcessor
from src.config import DIRECTORIES
import logging


class StatementHandler(FileSystemEventHandler):
    """
    Event handler for processing financial statement files.

    Monitors inbox directory for new statement files and delegates processing
    to FileProcessor. Simplified to focus on event detection and delegation.

    Attributes:
        file_processor: FileProcessor for complete file processing workflow
        logger: Logger instance for tracking operations
    """

    def __init__(self):
        """Initialize handler with file processor."""
        self.file_processor = FileProcessor()
        self.logger = logging.getLogger(__name__)
        self.logger.info('StatementHandler initialized with FileProcessor')

    def on_created(self, event):
        """
        Handle file creation events in inbox directory.

        Delegates file processing to FileProcessor and logs results based on
        ProcessingResult status. Simplified to focus on event detection.

        Args:
            event: FileSystemEvent from watchdog

        Notes:
            - Ignores directories and hidden files
            - Only processes .xlsx, .csv, .pdf files
            - Waits 1 second for file write completion
            - Delegates all processing logic to FileProcessor
            - Logs appropriate messages based on processing outcome
        """
        # Ignore directory events
        if event.is_directory:
            return

        filepath = event.src_path
        filename = os.path.basename(filepath)

        # Ignore hidden files and unsupported formats
        if filename.startswith('.') or not filename.endswith(('.xlsx', '.xls', '.csv', '.pdf')):
            self.logger.debug(f'Ignoring file: {filename}')
            return

        # Wait for file write completion
        time.sleep(1)

        # Delegate to FileProcessor
        result = self.file_processor.process_file(Path(filepath))

        # Cleanup old archived files (automatic maintenance)
        cleanup_result = self.file_processor.cleanup_old_archives()
        if cleanup_result['deleted_count'] > 0:
            self.logger.info(
                f'Archive cleanup: {cleanup_result["deleted_count"]} old files deleted, '
                f'{cleanup_result["skipped_count"]} kept'
            )

        # Log based on processing result
        if result.is_success():
            self.logger.info(
                f'Successfully processed: {filename} '
                f'({result.transaction_count} transactions, '
                f'file_id={result.file_id}, '
                f'hash={result.file_hash[:16]}...)'
            )
        elif result.is_duplicate():
            self.logger.warning(
                f'Duplicate file skipped: {filename} '
                f'(hash={result.file_hash[:16]}..., {result.message})'
            )
        elif result.is_error():
            self.logger.error(
                f'Processing failed: {filename} - {result.message}'
            )
            # Move problematic file to unknown directory if it still exists
            if os.path.exists(filepath):
                self._move_to_unknown(filepath)

    def _move_to_unknown(self, filepath):
        """
        Move unidentifiable or problematic file to unknown directory.

        Args:
            filepath: Path to the file to move

        Notes:
            - Logs the operation
            - Handles errors silently (file may already be moved)
        """
        try:
            filename = os.path.basename(filepath)
            dest = os.path.join(DIRECTORIES['unknown'], filename)

            # Handle duplicate filenames
            if os.path.exists(dest):
                base, ext = os.path.splitext(filename)
                timestamp = int(time.time())
                dest = os.path.join(DIRECTORIES['unknown'], f'{base}_{timestamp}{ext}')

            shutil.move(filepath, dest)
            self.logger.info(f'Moved to unknown: {filename}')
        except Exception as e:
            self.logger.error(f'Error moving file to unknown: {e}')
