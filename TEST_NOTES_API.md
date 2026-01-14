# Testing the Notes API Endpoint

## Prerequisites

1. Backend server running on `http://localhost:8000`
2. Valid authentication token
3. Existing transaction ID to test with

## Quick Test Guide

### 1. Get Test Transaction ID

```bash
# Get first transaction (replace with your auth token)
curl -s "http://localhost:8000/api/transactions?limit=1" \
  -H "Authorization: Bearer YOUR_TOKEN" | jq '.data[0].id'
```

### 2. Update Notes

```bash
# Update notes for transaction
curl -X PATCH "http://localhost:8000/api/transactions/{TRANSACTION_ID}/notes" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{"notes": "Test note - backend working!"}' | jq .
```

Expected Response:
```json
{
  "id": 123,
  "date": "2026.01.14",
  "category": "식비",
  "merchant_name": "스타벅스",
  "amount": 5000,
  "institution": "하나카드",
  "notes": "Test note - backend working!",
  "transaction_year": 2026,
  "transaction_month": 1,
  "category_id": 1,
  "institution_id": 1,
  "file_id": null,
  "row_number_in_file": null,
  "created_at": "2026-01-14T10:30:00"
}
```

### 3. Clear Notes

```bash
# Clear notes by setting to null
curl -X PATCH "http://localhost:8000/api/transactions/{TRANSACTION_ID}/notes" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{"notes": null}' | jq .
```

### 4. Verify in List Query

```bash
# Verify notes appear in list query
curl -s "http://localhost:8000/api/transactions?limit=10" \
  -H "Authorization: Bearer YOUR_TOKEN" | jq '.data[] | {id, merchant_name, notes}'
```

## Unit Tests

Run comprehensive test suite:

```bash
# Activate virtual environment
source .venv/bin/activate

# Run all CRUD API tests (includes 9 notes tests)
python -m unittest tests.test_transactions_crud_api.TestTransactionsCRUDAPI -v

# Run repository tests (includes 8 notes tests)
python -m unittest tests.test_transaction_repository.TestTransactionRepositoryCRUD -v

# Run specific notes tests
python -m unittest tests.test_transactions_crud_api.TestTransactionsCRUDAPI.test_update_notes_manual_transaction -v
```

## Database Verification

```bash
# Query notes directly from database
source .venv/bin/activate
python3 -c "
import sqlite3
conn = sqlite3.connect('data/expense_tracker.db')
conn.row_factory = sqlite3.Row
cursor = conn.execute('SELECT id, merchant_name, notes FROM transactions WHERE notes IS NOT NULL LIMIT 5')
for row in cursor:
    print(f'ID: {row[\"id\"]}, Merchant: {row[\"merchant_name\"]}, Notes: {row[\"notes\"]}')
conn.close()
"
```

## Error Cases

### 404 - Transaction Not Found
```bash
curl -X PATCH "http://localhost:8000/api/transactions/999999/notes" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{"notes": "Test"}' | jq .
```

Expected:
```json
{
  "detail": "거래 내역을 찾을 수 없습니다. (ID: 999999)"
}
```

### 401 - Unauthorized
```bash
curl -X PATCH "http://localhost:8000/api/transactions/123/notes" \
  -H "Content-Type: application/json" \
  -d '{"notes": "Test"}' | jq .
```

Expected:
```json
{
  "detail": "Not authenticated"
}
```

## Key Test Cases

1. **Manual Transaction Notes**: ✅ Should work
2. **Parsed Transaction Notes**: ✅ Should work (no file_id validation)
3. **Clear Notes (null)**: ✅ Should set to NULL
4. **Empty String**: ✅ Should store empty string
5. **Long Notes (500 chars)**: ✅ Should work
6. **Non-existent Transaction**: ✅ Should return 404
7. **Deleted Transaction**: ✅ Should return 404
8. **No Authentication**: ✅ Should return 401

## Frontend Integration Checklist

- [ ] Add notes column to transactions table
- [ ] Implement inline editing for notes
- [ ] Call PATCH endpoint on save
- [ ] Handle loading/error states
- [ ] Display null vs empty string appropriately
- [ ] Add proper error handling (404, 401, etc.)
- [ ] Test with both manual and parsed transactions
- [ ] Test clearing notes

## Notes

- Notes can be up to 500 characters (enforced at API level)
- Database column is TEXT (no length limit)
- Notes field is optional (can be null)
- Works for BOTH manual and parsed transactions
- Updates `updated_at` timestamp automatically
