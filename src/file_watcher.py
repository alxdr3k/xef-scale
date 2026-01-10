"""
FileWatcher for monitoring inbox directory and processing statement files.
Uses watchdog library to detect new files and orchestrate the parsing workflow.
"""

import time
import os
import shutil
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
from src.router import StatementRouter
from src.data_loader import DataLoader
from src.parsers.hana_parser import HanaCardParser
from src.config import DIRECTORIES
import logging


class StatementHandler(FileSystemEventHandler):
    """
    Event handler for processing financial statement files.

    Monitors inbox directory for new statement files, identifies the institution,
    parses transactions, saves to master ledger, and archives processed files.

    Attributes:
        router: StatementRouter for identifying financial institutions
        loader: DataLoader for saving transactions and archiving files
        parsers: Dictionary mapping institution codes to parser instances
        logger: Logger instance for tracking operations
    """

    def __init__(self):
        """Initialize handler with router, loader, and parser instances."""
        self.router = StatementRouter()
        self.loader = DataLoader()
        self.parsers = {
            'HANA': HanaCardParser()
            # Future: Add more parsers here (TOSS, KAKAO, SHINHAN)
        }
        self.logger = logging.getLogger(__name__)
        self.logger.info('StatementHandler initialized with parsers: ' + ', '.join(self.parsers.keys()))

    def on_created(self, event):
        """
        Handle file creation events in inbox directory.

        Orchestrates the complete workflow:
        1. Identifies institution using StatementRouter
        2. Gets appropriate parser instance
        3. Parses file to extract transactions
        4. Saves transactions using DataLoader
        5. Archives processed file
        6. Moves unidentifiable files to unknown/ directory

        Args:
            event: FileSystemEvent from watchdog

        Notes:
            - Ignores directories and hidden files
            - Only processes .xlsx, .csv, .pdf files
            - Waits 1 second for file write completion
            - Comprehensive error handling with logging
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

        try:
            self.logger.info(f'Processing new file: {filename}')

            # Step 1: Identify institution
            institution = self.router.identify(filepath)

            if not institution:
                self.logger.warning(f'Could not identify institution for: {filename}')
                self._move_to_unknown(filepath)
                return

            if institution not in self.parsers:
                self.logger.warning(f'No parser available for {institution}: {filename}')
                self._move_to_unknown(filepath)
                return

            self.logger.info(f'Identified as {institution} statement: {filename}')

            # Step 2: Get appropriate parser
            parser = self.parsers[institution]

            # Step 3: Parse file to extract transactions
            transactions = parser.parse(filepath)

            if not transactions:
                self.logger.warning(f'No transactions extracted from: {filename}')
                self.loader.archive_file(filepath)
                return

            self.logger.info(f'Extracted {len(transactions)} transactions from: {filename}')

            # Step 4: Save transactions to master ledger
            self.loader.save(transactions)

            # Step 5: Archive processed file
            self.loader.archive_file(filepath)

            self.logger.info(f'Successfully processed: {filename} ({len(transactions)} transactions)')

        except FileNotFoundError:
            self.logger.error(f'File not found (may have been moved): {filename}')
        except Exception as e:
            self.logger.error(f'Error processing {filename}: {e}', exc_info=True)
            # Move problematic file to unknown directory
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
