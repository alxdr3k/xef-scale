#!/usr/bin/env python3
"""
Excel Parser for Korean Financial Statements
Supports: Hana Card, Shinhan Card, Toss Bank, Kakao Bank
"""

import sys
import json
import re
import warnings
import os
from datetime import datetime
from pathlib import Path
from contextlib import redirect_stdout, redirect_stderr
from io import StringIO

# Suppress all warnings
warnings.filterwarnings('ignore')

# Suppress xlrd's direct print statements by setting verbosity
os.environ['XLRD_VERBOSITY'] = '0'

try:
    import pandas as pd
except ImportError:
    print(json.dumps({"error": "pandas not installed. Run: pip3 install pandas openpyxl xlrd"}))
    sys.exit(1)

# Institution signatures for identification
SIGNATURES = {
    'hana_card': ['하나카드', '이용일', '가맹점명', '이용대금 명세서', '거래일자'],
    'shinhan_card': ['신한카드', '이용일자', '승인번호'],
    'toss_bank': ['토스뱅크', 'Toss', '수신자', '거래유형'],
    'kakao_bank': ['kakao', '카카오뱅크', '거래일시', '거래구분'],
}


def identify_institution(df, file_content=""):
    """Identify financial institution from dataframe content"""
    # Convert first 20 rows to string for matching
    content = file_content
    if df is not None:
        try:
            sample = df.head(20).to_string()
            content = content + " " + sample
        except:
            pass

    for institution, keywords in SIGNATURES.items():
        for keyword in keywords:
            if keyword in content:
                return institution
    return None


def parse_date(date_str):
    """Parse various Korean date formats"""
    if pd.isna(date_str):
        return None

    date_str = str(date_str).strip()

    formats = [
        '%Y.%m.%d',
        '%Y-%m-%d',
        '%Y/%m/%d',
        '%y.%m.%d',
        '%y-%m-%d',
    ]

    for fmt in formats:
        try:
            dt = datetime.strptime(date_str, fmt)
            # Handle 2-digit years
            if dt.year < 100:
                dt = dt.replace(year=2000 + dt.year)
            return dt.strftime('%Y-%m-%d')
        except ValueError:
            continue

    return None


def parse_amount(amount):
    """Parse amount, handling various formats"""
    if pd.isna(amount):
        return 0

    if isinstance(amount, (int, float)):
        return abs(int(amount))

    # Remove currency symbols, commas, spaces
    cleaned = re.sub(r'[^\d.-]', '', str(amount))
    try:
        return abs(int(float(cleaned)))
    except ValueError:
        return 0


def parse_hana_card(df):
    """Parse Hana Card statement"""
    transactions = []

    # Find header row (contains '거래일자')
    header_row = None
    for idx, row in df.iterrows():
        if '거래일자' in str(row.values):
            header_row = idx
            break

    if header_row is None:
        return transactions

    # Parse from header_row + 1
    for idx in range(header_row + 1, len(df)):
        row = df.iloc[idx]

        # Skip empty rows
        if pd.isna(row.iloc[0]):
            continue

        first_cell = str(row.iloc[0])

        # Skip card info rows
        if '하나카드' in first_cell or '본인' in first_cell:
            continue

        # Check date format
        date_str = first_cell.strip()
        if not re.match(r'^\d{4}\.\d{2}\.\d{2}$', date_str):
            continue

        date = parse_date(date_str)
        if not date:
            continue

        # Get merchant (column 1)
        merchant = str(row.iloc[1]).strip() if len(row) > 1 and pd.notna(row.iloc[1]) else ''
        if not merchant or merchant == 'nan':
            continue

        # Get amount (column 2)
        amount = parse_amount(row.iloc[2]) if len(row) > 2 else 0
        if amount <= 0:
            continue

        transactions.append({
            'date': date,
            'merchant': merchant,
            'amount': amount,
            'description': merchant,
            'institution_identifier': 'hana_card'
        })

    return transactions


def parse_shinhan_card(df):
    """Parse Shinhan Card statement"""
    transactions = []

    # Find header row (contains '이용일자')
    header_row = None
    for idx, row in df.iterrows():
        row_str = ' '.join(str(v) for v in row.values if pd.notna(v))
        if '이용일자' in row_str:
            header_row = idx
            break

    if header_row is None:
        return transactions

    for idx in range(header_row + 1, len(df)):
        row = df.iloc[idx]

        if pd.isna(row.iloc[0]):
            continue

        date = parse_date(row.iloc[0])
        if not date:
            continue

        # Shinhan format: date, merchant, amount, ...
        merchant = str(row.iloc[1]).strip() if len(row) > 1 and pd.notna(row.iloc[1]) else ''
        if not merchant or merchant == 'nan':
            continue

        amount = parse_amount(row.iloc[2]) if len(row) > 2 else 0
        if amount <= 0:
            continue

        transactions.append({
            'date': date,
            'merchant': merchant,
            'amount': amount,
            'description': merchant,
            'institution_identifier': 'shinhan_card'
        })

    return transactions


def parse_toss_bank(df):
    """Parse Toss Bank statement"""
    transactions = []

    # Find header row
    header_row = None
    for idx, row in df.iterrows():
        row_str = ' '.join(str(v) for v in row.values if pd.notna(v))
        if '거래일시' in row_str or '거래유형' in row_str:
            header_row = idx
            break

    if header_row is None:
        return transactions

    for idx in range(header_row + 1, len(df)):
        row = df.iloc[idx]

        if pd.isna(row.iloc[0]):
            continue

        date = parse_date(row.iloc[0])
        if not date:
            continue

        merchant = str(row.iloc[1]).strip() if len(row) > 1 and pd.notna(row.iloc[1]) else ''
        if not merchant or merchant == 'nan':
            continue

        amount = parse_amount(row.iloc[2]) if len(row) > 2 else 0
        if amount <= 0:
            continue

        transactions.append({
            'date': date,
            'merchant': merchant,
            'amount': amount,
            'description': merchant,
            'institution_identifier': 'toss_bank'
        })

    return transactions


def parse_kakao_bank(df):
    """Parse Kakao Bank statement"""
    transactions = []

    # Find header row
    header_row = None
    for idx, row in df.iterrows():
        row_str = ' '.join(str(v) for v in row.values if pd.notna(v))
        if '거래일시' in row_str or '거래구분' in row_str:
            header_row = idx
            break

    if header_row is None:
        return transactions

    for idx in range(header_row + 1, len(df)):
        row = df.iloc[idx]

        if pd.isna(row.iloc[0]):
            continue

        date = parse_date(row.iloc[0])
        if not date:
            continue

        merchant = str(row.iloc[1]).strip() if len(row) > 1 and pd.notna(row.iloc[1]) else ''
        if not merchant or merchant == 'nan':
            continue

        amount = parse_amount(row.iloc[2]) if len(row) > 2 else 0
        if amount <= 0:
            continue

        transactions.append({
            'date': date,
            'merchant': merchant,
            'amount': amount,
            'description': merchant,
            'institution_identifier': 'kakao_bank'
        })

    return transactions


def read_excel_file(file_path):
    """Read Excel file with appropriate engine"""
    path = Path(file_path)
    ext = path.suffix.lower()

    # Capture stdout to suppress xlrd warnings
    old_stdout = sys.stdout
    sys.stdout = StringIO()

    try:
        if ext == '.xls':
            # Old Excel format - requires xlrd
            try:
                import xlrd
                # Set xlrd verbosity to 0 to suppress warnings
                result = pd.read_excel(file_path, engine='xlrd', header=None)
                return result
            except ImportError:
                return {"error": "xlrd not installed. Run: pip3 install xlrd"}
        else:
            # xlsx format - use openpyxl
            return pd.read_excel(file_path, engine='openpyxl', header=None)
    except Exception as e:
        return {"error": f"Failed to read file: {str(e)}"}
    finally:
        # Restore stdout
        sys.stdout = old_stdout


def main():
    if len(sys.argv) < 2:
        print(json.dumps({"error": "Usage: parse_excel.py <file_path>"}))
        sys.exit(1)

    file_path = sys.argv[1]

    if not Path(file_path).exists():
        print(json.dumps({"error": f"File not found: {file_path}"}))
        sys.exit(1)

    # Read file
    result = read_excel_file(file_path)
    if isinstance(result, dict) and 'error' in result:
        print(json.dumps(result))
        sys.exit(1)

    df = result

    # Read raw content for institution detection
    try:
        with open(file_path, 'rb') as f:
            raw_content = f.read(5000).decode('utf-8', errors='ignore')
    except:
        raw_content = ""

    # Identify institution
    institution = identify_institution(df, raw_content)

    if not institution:
        print(json.dumps({
            "error": "Unknown institution format",
            "institution": None,
            "transactions": []
        }))
        sys.exit(1)

    # Parse based on institution
    parsers = {
        'hana_card': parse_hana_card,
        'shinhan_card': parse_shinhan_card,
        'toss_bank': parse_toss_bank,
        'kakao_bank': parse_kakao_bank,
    }

    parser = parsers.get(institution)
    if not parser:
        print(json.dumps({
            "error": f"No parser for institution: {institution}",
            "institution": institution,
            "transactions": []
        }))
        sys.exit(1)

    transactions = parser(df)

    print(json.dumps({
        "institution": institution,
        "transactions": transactions,
        "count": len(transactions)
    }))


if __name__ == '__main__':
    main()
