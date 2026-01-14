# Feature 1 Backend Implementation: Notes Column API

## Summary

Successfully implemented backend support for the notes column feature, allowing users to add, update, and clear notes on ANY transaction (both manual and parsed transactions).

## Changes Made

### 1. Schema Updates (`/backend/api/schemas.py`)

Added `notes` field to `TransactionResponse` schema:
```python
class TransactionResponse(TransactionBase):
    """Transaction response schema with database fields."""
    id: int
    transaction_year: int
    transaction_month: int
    category_id: int
    institution_id: int
    file_id: Optional[int] = None
    row_number_in_file: Optional[int] = None
    notes: Optional[str] = None  # NEW FIELD
    created_at: str
```

### 2. API Route Updates (`/backend/api/routes/transactions.py`)

#### Added Import
```python
from fastapi import APIRouter, Depends, HTTPException, status, Query, Body
```

#### Updated Response Mapper
Modified `_db_row_to_transaction_response()` to include notes:
```python
return TransactionResponse(
    # ... other fields ...
    notes=row.get('notes'),  # NEW LINE
    created_at=row['created_at']
)
```

#### New PATCH Endpoint
Added `PATCH /api/transactions/{transaction_id}/notes` endpoint:
- Accepts `notes: Optional[str]` in request body
- Works for BOTH manual and parsed transactions (no file_id validation)
- Returns full `TransactionResponse` with updated notes
- Returns 404 if transaction not found
- Requires authentication

### 3. Repository Updates (`/src/db/repository.py`)

Added `update_notes()` method to `TransactionRepository`:
```python
def update_notes(self, transaction_id: int, notes: Optional[str]) -> bool:
    """
    Update notes for any transaction (including parsed transactions).

    Unlike other transaction fields, notes can be updated for BOTH manual and
    file-based transactions.
    """
    query = '''
        UPDATE transactions
        SET notes = ?, updated_at = CURRENT_TIMESTAMP
        WHERE id = ? AND deleted_at IS NULL
    '''
    cursor = self.conn.execute(query, (notes, transaction_id))
    self.conn.commit()
    return cursor.rowcount > 0
```

### 4. Test Coverage

#### Repository Tests (`tests/test_transaction_repository.py`)
Added 8 comprehensive tests for `update_notes()` method:
- `test_update_notes_manual_transaction`
- `test_update_notes_parsed_transaction`
- `test_update_notes_clear_notes`
- `test_update_notes_empty_string`
- `test_update_notes_nonexistent_transaction`
- `test_update_notes_deleted_transaction`
- `test_update_notes_preserves_other_fields`
- `test_update_notes_long_text`

#### API Tests (`tests/test_transactions_crud_api.py`)
Added 9 comprehensive tests for PATCH endpoint:
- `test_update_notes_manual_transaction`
- `test_update_notes_parsed_transaction`
- `test_update_notes_clear_notes`
- `test_update_notes_empty_string`
- `test_update_notes_not_found`
- `test_update_notes_response_structure`
- `test_update_notes_persists_in_database`
- `test_get_transactions_includes_notes`
- `test_update_notes_without_authentication`

All tests pass successfully (44/44 tests in CRUD suite).

## API Usage

### Update Notes
```bash
PATCH /api/transactions/{transaction_id}/notes
Content-Type: application/json
Authorization: Bearer {token}

{
  "notes": "회의 중 커피 구매"
}
```

### Clear Notes
```bash
PATCH /api/transactions/{transaction_id}/notes
Content-Type: application/json
Authorization: Bearer {token}

{
  "notes": null
}
```

### Response
```json
{
  "id": 123,
  "date": "2026.01.14",
  "category": "식비",
  "merchant_name": "스타벅스",
  "amount": 5000,
  "institution": "하나카드",
  "notes": "회의 중 커피 구매",
  "transaction_year": 2026,
  "transaction_month": 1,
  "category_id": 1,
  "institution_id": 1,
  "file_id": null,
  "row_number_in_file": null,
  "created_at": "2026-01-14T10:30:00"
}
```

## Key Design Decisions

1. **No File ID Validation**: Unlike other transaction fields, notes can be updated for BOTH manual and parsed transactions. This allows users to add context to any transaction regardless of its source.

2. **Separate Endpoint**: Created a dedicated PATCH endpoint (`/notes`) rather than extending PUT endpoint to:
   - Provide a lightweight operation focused on notes only
   - Avoid triggering file_id validation in the update() method
   - Follow RESTful partial update pattern

3. **Null vs Empty String**: The API distinguishes between:
   - `null`: Clears notes (sets to NULL in DB)
   - `""`: Sets notes to empty string

4. **Existing Column**: The `transactions.notes` column already existed in the database (TEXT type), so no migration was needed.

5. **Query Compatibility**: Since `get_by_id()` and `get_filtered()` use `SELECT t.*`, they automatically include the notes column without modification.

## Testing Verification

All tests pass successfully:
```
tests/test_transaction_repository.py: 8 new tests (all passing)
tests/test_transactions_crud_api.py: 9 new tests (all passing)
Total CRUD API tests: 44/44 passing
```

## Next Steps (Frontend Integration)

The backend is now ready for frontend integration. The frontend team should:

1. Add notes column to the transactions table UI
2. Implement inline editing for notes field
3. Call `PATCH /api/transactions/{id}/notes` on edit
4. Handle null values (empty notes) appropriately
5. Add proper error handling (404, 401, etc.)

## Database Schema

The notes column is already present:
```sql
CREATE TABLE transactions (
    -- ... other columns ...
    notes TEXT,  -- Supports up to 500 characters (enforced at API level)
    -- ... other columns ...
);
```

## Validation

- Notes field is optional (`Optional[str]`)
- Maximum length: 500 characters (enforced in `TransactionCreateRequest` and `TransactionUpdateRequest`)
- No maximum at database level (TEXT column)
- API-level validation ensures consistency

## Files Modified

1. `/backend/api/schemas.py` - Added notes field to TransactionResponse
2. `/backend/api/routes/transactions.py` - Added PATCH endpoint and updated response mapper
3. `/src/db/repository.py` - Added update_notes() method
4. `/tests/test_transaction_repository.py` - Added 8 repository tests
5. `/tests/test_transactions_crud_api.py` - Added 9 API tests

## Implementation Date

January 14, 2026
