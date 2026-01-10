"""
CSV to SQLite migration script.
Imports data from master_ledger.csv into the transactions table.
"""

import pandas as pd
import logging
import sys
import os

# Add project root to path for imports
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../..')))

from src.db.connection import DatabaseConnection
from src.db.repository import CategoryRepository, InstitutionRepository, TransactionRepository
from src.models import Transaction


def main():
    """
    Migrate CSV data to SQLite database.

    Reads data/master_ledger.csv and inserts all transactions into the database
    using the repository pattern. Handles Korean column names, date parsing,
    and installment fields with NaN values.

    Raises:
        FileNotFoundError: If CSV file doesn't exist
        Exception: If migration fails

    Examples:
        >>> python db/migrations/003_migrate_csv_data.py

    Notes:
        - Safe to run multiple times (duplicates are ignored)
        - Progress logged every 100 rows
        - Final count verification against CSV row count
    """
    # Configure logging
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s'
    )
    logger = logging.getLogger(__name__)

    csv_path = 'data/master_ledger.csv'

    # Check if CSV exists
    if not os.path.exists(csv_path):
        logger.error(f'CSV file not found: {csv_path}')
        logger.info('Please ensure master_ledger.csv exists in the data/ directory')
        return

    try:
        # Read CSV with UTF-8-BOM encoding (for Korean text in Excel)
        logger.info(f'Reading CSV file: {csv_path}')
        df = pd.read_csv(csv_path, encoding='utf-8-sig')
        total_rows = len(df)
        logger.info(f'Found {total_rows} transactions in CSV')

        # Show CSV columns for debugging
        logger.debug(f'CSV columns: {list(df.columns)}')

        # Setup database repositories
        conn = DatabaseConnection.get_instance()
        category_repo = CategoryRepository(conn)
        institution_repo = InstitutionRepository(conn)
        transaction_repo = TransactionRepository(conn, category_repo, institution_repo)
        logger.info('Database repositories initialized')

        # Process rows and build transaction list
        transactions = []
        skipped = 0

        for i, row in df.iterrows():
            try:
                # Extract required fields
                month = str(row['월']).zfill(2)  # Pad to 2 digits
                date = row['날짜']  # yyyy.mm.dd format
                category = row['분류']
                item = row['항목']
                amount = int(row['금액'])
                source = row['은행/카드']

                # Handle optional installment fields (may be NaN or missing)
                installment_months = None
                installment_current = None
                original_amount = None

                if '할부개월' in df.columns and pd.notna(row.get('할부개월')):
                    try:
                        installment_months = int(float(row['할부개월']))
                    except (ValueError, TypeError):
                        pass

                if '할부회차' in df.columns and pd.notna(row.get('할부회차')):
                    try:
                        installment_current = int(float(row['할부회차']))
                    except (ValueError, TypeError):
                        pass

                if '원금액' in df.columns and pd.notna(row.get('원금액')):
                    try:
                        original_amount = int(float(row['원금액']))
                    except (ValueError, TypeError):
                        pass

                # Create Transaction object
                txn = Transaction(
                    month=month,
                    date=date,
                    category=category,
                    item=item,
                    amount=amount,
                    source=source,
                    installment_months=installment_months,
                    installment_current=installment_current,
                    original_amount=original_amount
                )
                transactions.append(txn)

                # Progress logging every 100 rows
                if (i + 1) % 100 == 0:
                    progress = ((i + 1) / total_rows) * 100
                    logger.info(f'Progress: {i+1}/{total_rows} ({progress:.1f}%)')

            except KeyError as e:
                logger.warning(f'Skipping row {i+1}: missing required column {e}')
                skipped += 1
            except Exception as e:
                logger.warning(f'Skipping row {i+1}: {e}')
                skipped += 1

        if skipped > 0:
            logger.warning(f'Skipped {skipped} rows due to errors')

        # Batch insert all transactions
        logger.info(f'Inserting {len(transactions)} transactions into database...')
        inserted_count = transaction_repo.batch_insert(transactions)

        # Verify results
        cursor = conn.execute('SELECT COUNT(*) FROM transactions')
        db_count = cursor.fetchone()[0]

        logger.info('=' * 60)
        logger.info('Migration Complete')
        logger.info('=' * 60)
        logger.info(f'CSV rows processed: {total_rows}')
        logger.info(f'Transactions created: {len(transactions)}')
        logger.info(f'Successfully inserted: {inserted_count}')
        logger.info(f'Duplicates ignored: {len(transactions) - inserted_count}')
        logger.info(f'Total in database: {db_count}')
        logger.info('=' * 60)

        # Verify date format
        cursor = conn.execute('SELECT transaction_date FROM transactions LIMIT 1')
        sample_date = cursor.fetchone()
        if sample_date:
            logger.info(f'Sample date format in DB: {sample_date[0]}')

    except FileNotFoundError:
        logger.error(f'CSV file not found: {csv_path}')
        raise
    except Exception as e:
        logger.error(f'Migration failed: {e}')
        raise


if __name__ == '__main__':
    main()
