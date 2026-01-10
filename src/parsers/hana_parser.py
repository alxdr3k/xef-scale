"""
HanaCardParser for parsing Hana Card Excel statement files.
First concrete implementation of StatementParser for 하나카드.
"""

import pandas as pd
import re
from typing import List
from src.parsers.base import StatementParser
from src.models import Transaction
import logging


class HanaCardParser(StatementParser):
    """
    Parser for Hana Card (하나카드) Excel statement files.

    Extracts transaction data from Hana Card statements, normalizes dates,
    and categorizes transactions using the inherited CategoryMatcher.

    Assumes CSV/Excel format with columns: date, merchant, amount
    Note: Real Hana Card format may differ - requires sample file to validate
    """

    def parse(self, file_path: str) -> List[Transaction]:
        """
        Parse Hana Card statement file and extract transactions.

        Reads Excel or CSV file, finds the transaction data section (after '거래일자' header),
        extracts transaction data, normalizes dates to yyyy.mm.dd format, and auto-categorizes.

        Args:
            file_path: Path to the Hana Card statement file (.xlsx or .csv)

        Returns:
            List of Transaction objects with source='하나카드'

        Raises:
            Exception: If file cannot be read or parsed

        Examples:
            >>> parser = HanaCardParser()
            >>> transactions = parser.parse('hana_statement.xlsx')
            >>> print(len(transactions))
            25

        Notes:
            - Finds '거래일자' row to locate start of transaction data
            - Skips metadata rows (header, summaries, card info)
            - Date format must be yyyy.mm.dd
            - Amount field may contain commas (automatically removed)
            - Uses inherited CategoryMatcher for auto-categorization
        """
        transactions = []
        logger = logging.getLogger(__name__)

        try:
            # Read file based on extension
            if file_path.endswith('.csv'):
                df = pd.read_csv(file_path, header=None)
            else:
                df = pd.read_excel(file_path, header=None)

            logger.info(f'Parsing Hana Card statement: {file_path} ({len(df)} rows)')

            # Find the row containing '거래일자' to locate transaction data start
            start_row = None
            for idx, row in df.iterrows():
                if '거래일자' in str(row.values):
                    start_row = idx + 1  # Data starts after header row
                    logger.debug(f'Found transaction header at row {idx}')
                    break

            if start_row is None:
                logger.warning('Could not find transaction header (거래일자) in file')
                return transactions

            # Skip one more row if it contains card info (e.g., "MG+ S 하나카드")
            if start_row < len(df):
                first_row = df.iloc[start_row]
                if '하나카드' in str(first_row.values) and not re.match(r'\d{4}\.\d{2}\.\d{2}', str(first_row[0])):
                    start_row += 1
                    logger.debug(f'Skipped card info row, starting at row {start_row}')

            # Process transaction rows
            for idx in range(start_row, len(df)):
                try:
                    row = df.iloc[idx]

                    # Extract and validate date (column 0: 거래일자)
                    raw_date = str(row[0]).strip()

                    # Check if date matches yyyy.mm.dd format
                    if not re.match(r'\d{4}\.\d{2}\.\d{2}', raw_date):
                        continue  # Skip non-data rows

                    # Extract merchant name (column 1: 가맹점명)
                    item_name = str(row[1]).strip()
                    if not item_name or item_name == 'nan':
                        continue  # Skip rows with missing merchant

                    # Extract original amount (column 2: 이용금액)
                    original_amount_str = str(row[2]).replace(',', '').strip()
                    if original_amount_str == 'nan' or not original_amount_str:
                        continue
                    original_amount = int(float(original_amount_str))

                    # Extract actual charged amount (column 5: 결제원금)
                    # This is the amount actually charged this billing period
                    charged_amount_str = str(row[5]).replace(',', '').strip() if len(row) > 5 else original_amount_str
                    if charged_amount_str == 'nan' or not charged_amount_str:
                        charged_amount = original_amount
                    else:
                        charged_amount = int(float(charged_amount_str))

                    # Skip transactions with 0 charged amount (cancelled or fully discounted)
                    if charged_amount == 0:
                        logger.debug(f'Skipped 0 amount transaction: {raw_date} {item_name}')
                        continue

                    # Extract installment info (column 3: 할부기간, column 4: 청구회차)
                    installment_months = None
                    installment_current = None
                    is_installment = False

                    if len(row) > 3:
                        installment_str = str(row[3]).strip()
                        if installment_str not in ['nan', '-', '']:
                            try:
                                installment_months = int(installment_str)
                                is_installment = True
                            except ValueError:
                                pass

                    if is_installment and len(row) > 4:
                        current_str = str(row[4]).strip()
                        if current_str not in ['nan', '-', '']:
                            try:
                                installment_current = int(current_str)
                            except ValueError:
                                pass

                    # Parse date components
                    yyyy, mm, dd = raw_date.split('.')

                    # Create transaction with auto-categorization
                    transaction = Transaction(
                        month=mm,
                        date=raw_date,
                        category=self.matcher.get_category(item_name),
                        item=item_name,
                        amount=charged_amount,  # Use actual charged amount (결제원금)
                        source='하나카드',
                        installment_months=installment_months if is_installment else None,
                        installment_current=installment_current if is_installment else None,
                        original_amount=original_amount if is_installment else None
                    )

                    transactions.append(transaction)

                except (ValueError, IndexError, AttributeError) as e:
                    logger.debug(f'Skipped row {idx}: {e}')
                    continue

            logger.info(f'Successfully parsed {len(transactions)} transactions from Hana Card statement')

        except FileNotFoundError:
            logger.error(f'File not found: {file_path}')
            raise
        except Exception as e:
            logger.error(f'Parse error for {file_path}: {e}')
            raise

        return transactions
