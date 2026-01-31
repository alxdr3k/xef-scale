#!/usr/bin/env python3
"""
Excel Parser for Korean Financial Statements
Supports: Hana Card, Shinhan Card, Toss Bank, Kakao Bank, Samsung Card
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
    'hana_card': ['하나카드', '가맹점명', '이용대금 명세서', '거래일자'],
    'shinhan_card': ['신한카드', '이용일자', '승인번호'],
    'toss_bank': ['토스뱅크', 'Toss', '수신자', '거래유형'],
    'kakao_bank': ['kakao', '카카오뱅크', '거래일시', '거래구분'],
    'samsung_card': ['삼성카드', '입금후잔액', '이용구분'],
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
        '%Y%m%d',
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
    """Parse amount, handling various formats (preserves sign for cancellations)"""
    if pd.isna(amount):
        return 0

    if isinstance(amount, (int, float)):
        return int(amount)

    # Remove currency symbols, commas, spaces
    cleaned = re.sub(r'[^\d.-]', '', str(amount))
    try:
        return int(float(cleaned))
    except ValueError:
        return 0


def find_column_indices(df, header_row_idx):
    """헤더 row에서 컬럼명을 읽어 인덱스 맵 반환"""
    header = df.iloc[header_row_idx]
    indices = {}

    # 컬럼명 매핑 (실제 Excel 헤더명 → 내부 키)
    column_mappings = {
        '거래일자': 'date',
        '가맹점명': 'merchant',
        '이용금액': 'original_amount',
        '혜택구분': 'benefit_category',
        '할부기간': 'installment_total',
        '청구회차': 'installment_month',
        '결제원금': 'monthly_amount',
        '이용혜택': 'benefit_type',
        '혜택금액': 'benefit_amount',
    }

    for col_idx, cell in enumerate(header):
        cell_str = str(cell).strip()
        for excel_name, key in column_mappings.items():
            if excel_name in cell_str:
                indices[key] = col_idx
                break

    return indices


def get_cell_safe(row, col_idx, default=''):
    """안전하게 셀 값 가져오기 (인덱스가 -1이거나 범위 밖이면 기본값 반환)"""
    if col_idx is None or col_idx < 0 or col_idx >= len(row):
        return default
    val = row.iloc[col_idx]
    return '' if pd.isna(val) else str(val).strip()


def parse_int_safe(text):
    """안전하게 정수 파싱"""
    if not text or text == 'nan':
        return None
    try:
        return int(float(text))
    except (ValueError, TypeError):
        return None


def parse_hana_card(df):
    """Parse Hana Card statement"""
    transactions = []

    # Find header row (contains '거래일자')
    header_row_idx = None
    for idx, row in df.iterrows():
        if '거래일자' in str(row.values):
            header_row_idx = idx
            break

    if header_row_idx is None:
        return transactions

    # 동적 컬럼 인덱스 찾기
    col = find_column_indices(df, header_row_idx)

    # 필수 컬럼 확인 (없으면 기본값 사용)
    date_col = col.get('date', 0)
    merchant_col = col.get('merchant', 1)
    original_amount_col = col.get('original_amount', 2)

    # Parse from header_row + 1
    for idx in range(header_row_idx + 1, len(df)):
        row = df.iloc[idx]

        # Skip empty rows
        if pd.isna(row.iloc[0]):
            continue

        first_cell = str(row.iloc[0])

        # Skip card info rows
        if '하나카드' in first_cell or '본인' in first_cell:
            continue

        # Check date format
        date_str = get_cell_safe(row, date_col)
        if not re.match(r'^\d{4}\.\d{2}\.\d{2}$', date_str):
            continue

        date = parse_date(date_str)
        if not date:
            continue

        # 가맹점명
        merchant = get_cell_safe(row, merchant_col)
        if not merchant or merchant == 'nan':
            continue

        # 금액 정보
        original_amount = parse_amount(get_cell_safe(row, original_amount_col))
        if original_amount == 0:
            continue

        # 할부 정보 (컬럼이 없으면 None)
        benefit_category = get_cell_safe(row, col.get('benefit_category'))
        installment_total = parse_int_safe(get_cell_safe(row, col.get('installment_total')))
        installment_month = parse_int_safe(get_cell_safe(row, col.get('installment_month')))
        monthly_amount = parse_amount(get_cell_safe(row, col.get('monthly_amount')))
        benefit_type = get_cell_safe(row, col.get('benefit_type'))
        benefit_amount = parse_amount(get_cell_safe(row, col.get('benefit_amount')))

        # 할부 여부 판단
        is_installment = benefit_category == '할부' or (installment_total and installment_total > 1)

        # amount 결정: 할부면 결제원금, 아니면 이용금액
        amount = monthly_amount if is_installment and monthly_amount != 0 else original_amount

        transactions.append({
            'date': date,
            'merchant': merchant,
            'amount': amount,
            'description': merchant,
            'original_amount': original_amount if is_installment else None,
            'installment_month': installment_month if is_installment else None,
            'installment_total': installment_total if is_installment else None,
            'benefit_type': benefit_type if benefit_type else None,
            'benefit_amount': benefit_amount if benefit_amount else None,
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
        if amount == 0:
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
        if amount == 0:
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
        if amount == 0:
            continue

        transactions.append({
            'date': date,
            'merchant': merchant,
            'amount': amount,
            'description': merchant,
            'institution_identifier': 'kakao_bank'
        })

    return transactions


def parse_samsung_card(df, file_path):
    """Parse Samsung Card statement (supports multiple sheets: 일시불, 할부)"""
    transactions = []

    # Read all sheets
    try:
        all_sheets = pd.read_excel(file_path, sheet_name=None, header=None, engine='openpyxl')
    except Exception:
        all_sheets = {'Sheet1': df}

    for sheet_name, sheet_df in all_sheets.items():
        # Find header row containing '이용일' and '가맹점'
        header_row_idx = None
        for idx, row in sheet_df.iterrows():
            row_str = ' '.join(str(v) for v in row.values if pd.notna(v))
            if '이용일' in row_str and '가맹점' in row_str:
                header_row_idx = idx
                break

        if header_row_idx is None:
            continue

        # Build column map from header
        header = sheet_df.iloc[header_row_idx]
        col_map = {}
        for col_idx, cell in enumerate(header):
            cell_str = str(cell).strip()
            if cell_str == '이용일':
                col_map['date'] = col_idx
            elif cell_str == '가맹점':
                col_map['merchant'] = col_idx
            elif cell_str == '이용금액':
                col_map['original_amount'] = col_idx
            elif cell_str == '원금':
                col_map['principal'] = col_idx
            elif cell_str == '개월':
                col_map['installment_total'] = col_idx
            elif cell_str == '회차':
                col_map['installment_month'] = col_idx
            elif cell_str == '이용혜택':
                col_map['benefit_type'] = col_idx
            elif cell_str == '혜택금액':
                col_map['benefit_amount'] = col_idx

        date_col = col_map.get('date', 0)
        merchant_col = col_map.get('merchant', 2)
        principal_col = col_map.get('principal')

        is_installment = '할부' in str(sheet_name)
        payment_type = 'installment' if is_installment else 'lump_sum'

        for idx in range(header_row_idx + 1, len(sheet_df)):
            row = sheet_df.iloc[idx]

            # Date
            date_val = row.iloc[date_col] if date_col < len(row) else None
            if pd.isna(date_val) or str(date_val).strip() == '':
                continue

            date = parse_date(str(date_val).strip())
            if not date:
                continue

            # Merchant
            merchant = get_cell_safe(row, merchant_col)
            if not merchant or merchant == 'nan' or '합계' in merchant:
                continue

            # Amount: use 원금 (principal) column - it's the numeric monthly charge
            amount = 0
            if principal_col is not None and principal_col < len(row) and pd.notna(row.iloc[principal_col]):
                try:
                    amount = int(float(row.iloc[principal_col]))
                except (ValueError, TypeError):
                    amount = 0

            if amount == 0:
                # Fallback to 이용금액
                original_col = col_map.get('original_amount')
                if original_col is not None:
                    amount = parse_amount(get_cell_safe(row, original_col))

            # Skip zero amounts only
            if amount == 0:
                continue

            tx = {
                'date': date,
                'merchant': merchant,
                'amount': amount,
                'description': merchant,
                'payment_type': payment_type,
                'institution_identifier': 'samsung_card'
            }

            # Original amount for installments
            if is_installment:
                orig = col_map.get('original_amount')
                if orig is not None:
                    orig_amount = parse_amount(get_cell_safe(row, orig))
                    if orig_amount != 0:
                        tx['original_amount'] = orig_amount
                inst_total = parse_int_safe(get_cell_safe(row, col_map.get('installment_total')))
                inst_month = parse_int_safe(get_cell_safe(row, col_map.get('installment_month')))
                if inst_total:
                    tx['installment_total'] = inst_total
                if inst_month:
                    tx['installment_month'] = inst_month

            # Benefit info
            benefit_type = get_cell_safe(row, col_map.get('benefit_type'))
            benefit_amount_val = parse_amount(get_cell_safe(row, col_map.get('benefit_amount')))
            if benefit_type and benefit_type.strip() and benefit_type.strip() != ' ':
                tx['benefit_type'] = benefit_type.strip()
            if benefit_amount_val:
                tx['benefit_amount'] = benefit_amount_val

            transactions.append(tx)

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
        'samsung_card': lambda d: parse_samsung_card(d, file_path),
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
