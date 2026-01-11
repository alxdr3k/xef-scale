# Temporary Import Scripts

This directory contains one-time scripts for importing historical transaction data.

## Purpose
Import transactions from 2024.txt and 2025.txt into the expense-tracker database.

## Usage

### Preview import (no database changes)
```bash
python scripts/temp_manual_import.py --dry-run
```

### Actual import
```bash
python scripts/temp_manual_import.py
```

### Verbose logging
```bash
python scripts/temp_manual_import.py --verbose
```

## Import Results

- **Total imported**: 1,177 transactions
- **2024.txt**: 307 transactions (24 zero amounts skipped)
- **2025.txt**: 881 transactions (30 date fallbacks)
- **Duplicates**: 11 detected and skipped
- **Institution**: All transactions tagged as "수동입력"

## Deletion Instructions

After verifying the import is complete, this entire directory can be safely deleted:

```bash
rm -rf scripts/
```

The imported data persists in the database and will not be affected by deleting these temporary scripts.

## Verification

To verify transactions were imported successfully:

```sql
sqlite3 data/expense_tracker.db "SELECT COUNT(*) FROM transactions WHERE institution_id = (SELECT id FROM financial_institutions WHERE name = '수동입력')"
```

Expected: ~1,177 transactions

## Files

- `temp_manual_import.py` - Main parser script
- `README.md` - This file

## Status

✅ Import completed successfully on 2026-01-11
