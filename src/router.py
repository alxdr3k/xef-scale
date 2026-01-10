"""
StatementRouter for identifying financial institutions from statement files.
Uses keyword matching on file headers to determine which parser to use.
"""

import pandas as pd
import pdfplumber
from src.config import INSTITUTION_KEYWORDS
import logging
from typing import Optional


class StatementRouter:
    """
    Identifies financial institution from statement file content.

    Reads file headers and searches for institution-specific keywords
    to determine which parser should be used. Supports Excel, CSV, and PDF files.

    Attributes:
        keywords: Dictionary mapping institution codes to keyword lists
        logger: Logger instance for tracking identification attempts
    """

    def __init__(self):
        """Initialize router with institution keywords and logger."""
        self.keywords = INSTITUTION_KEYWORDS
        self.logger = logging.getLogger(__name__)

    def identify(self, file_path: str) -> Optional[str]:
        """
        Identify financial institution from file content.

        Reads the first 10 rows for Excel/CSV files or first page for PDFs,
        then searches for institution keywords in the content.

        Args:
            file_path: Path to the statement file

        Returns:
            Institution code (e.g., 'TOSS', 'KAKAO', 'SHINHAN', 'HANA')
            or None if institution cannot be identified

        Examples:
            >>> router = StatementRouter()
            >>> router.identify('hana_statement.xlsx')
            'HANA'
            >>> router.identify('unknown_file.xlsx')
            None

        Raises:
            No exceptions raised - errors are logged and None is returned
        """
        try:
            # Read file content based on file type
            if file_path.endswith('.xlsx') or file_path.endswith('.xls'):
                df = pd.read_excel(file_path, nrows=50)
                content = df.to_string()
            elif file_path.endswith('.csv'):
                df = pd.read_csv(file_path, nrows=50)
                content = df.to_string()
            elif file_path.endswith('.pdf'):
                with pdfplumber.open(file_path) as pdf:
                    if len(pdf.pages) > 0:
                        content = pdf.pages[0].extract_text()
                    else:
                        self.logger.warning(f'PDF file has no pages: {file_path}')
                        return None
            else:
                self.logger.warning(f'Unsupported file type: {file_path}')
                return None

            # Search for institution keywords in content
            for institution, keywords in self.keywords.items():
                if any(kw in content for kw in keywords):
                    self.logger.info(f'Identified {institution} from file: {file_path}')
                    return institution

            self.logger.warning(f'Could not identify institution from file: {file_path}')
            return None

        except FileNotFoundError:
            self.logger.error(f'File not found: {file_path}')
            return None
        except Exception as e:
            self.logger.error(f'Error identifying file {file_path}: {e}')
            return None
