"""
DataLoader for CSV persistence and file archiving.
Handles saving transactions to master ledger and archiving processed files.
"""

import pandas as pd
import shutil
import os
import time
from typing import List
from src.models import Transaction
from src.config import DIRECTORIES
import logging


class DataLoader:
    """
    Manages data persistence and file archiving for expense tracking system.

    Saves transactions to master_ledger.csv with Korean encoding (UTF-8-BOM)
    and archives processed statement files to prevent reprocessing.

    Attributes:
        ledger_path: Path to master_ledger.csv file
        archive_dir: Path to archive directory for processed files
        logger: Logger instance for tracking operations
    """

    def __init__(self):
        """Initialize DataLoader with paths from config and logger."""
        self.ledger_path = os.path.join(DIRECTORIES['data'], 'master_ledger.csv')
        self.archive_dir = DIRECTORIES['archive']
        self.logger = logging.getLogger(__name__)

    def save(self, transactions: List[Transaction]):
        """
        Append transactions to master ledger CSV.

        Creates the CSV file with Korean headers if it doesn't exist.
        Appends to existing file without duplicating headers.
        Uses UTF-8-BOM encoding for proper Korean text display in Excel.

        Args:
            transactions: List of Transaction objects to save

        Examples:
            >>> loader = DataLoader()
            >>> transactions = [Transaction(...), Transaction(...)]
            >>> loader.save(transactions)

        Notes:
            - Empty transaction lists are ignored
            - Headers are written only if file doesn't exist
            - Uses UTF-8-BOM encoding for Excel compatibility
        """
        if not transactions:
            self.logger.info('No transactions to save')
            return

        # Convert transactions to DataFrame using to_dict() method
        df = pd.DataFrame([t.to_dict() for t in transactions])

        # Check if file exists to determine if headers are needed
        file_exists = os.path.exists(self.ledger_path)

        # Append to CSV with Korean encoding
        df.to_csv(
            self.ledger_path,
            mode='a',
            header=not file_exists,
            index=False,
            encoding='utf-8-sig'  # UTF-8-BOM for Korean text
        )

        self.logger.info(f'Saved {len(transactions)} transactions to master ledger')

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
