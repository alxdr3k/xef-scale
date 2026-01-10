# Users Table Implementation Documentation

**Task ID**: d869c9c9 - Phase1-DB users table schema and migration

**Date**: 2026-01-11

**Status**: COMPLETED

## Overview

Implemented the users table schema and UserRepository for Google OAuth-based authentication system. This establishes the foundation for multi-user support in the expense tracker application.

## Database Schema

### Table: `users`

```sql
CREATE TABLE users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,

    -- Basic profile information
    email TEXT NOT NULL UNIQUE,
    google_id TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    profile_picture_url TEXT,

    -- OAuth tokens (encrypted by application layer)
    access_token TEXT,
    refresh_token TEXT,
    token_expires_at DATETIME,

    -- Account status and metadata
    is_active BOOLEAN DEFAULT 1,
    last_login_at DATETIME,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

### Indexes

1. **idx_users_email** (UNIQUE): Fast email-based lookups during login
2. **idx_users_google_id** (UNIQUE): Fast Google ID lookups during OAuth callback
3. **idx_users_active** (FILTERED): Optimized queries for active users only
4. **idx_users_last_login** (DESC): Sorted by recent login for admin dashboards

### Triggers

- **update_users_timestamp**: Automatically updates `updated_at` on any UPDATE

## Security Considerations

### Token Encryption

**CRITICAL**: The database stores encrypted token values only. Application layer MUST handle encryption/decryption.

**Recommended Approach**:
```python
from cryptography.fernet import Fernet

# Generate key (store securely in environment variable)
key = Fernet.generate_key()
cipher = Fernet(key)

# Encrypt before storing
encrypted_token = cipher.encrypt(access_token.encode()).decode()
user_repo.update_tokens(user_id, encrypted_token, ...)

# Decrypt after retrieving
user = user_repo.get_by_id(user_id)
decrypted_token = cipher.decrypt(user['access_token'].encode()).decode()
```

### Environment Variables Required

```bash
# .env
FERNET_ENCRYPTION_KEY=<base64-encoded-key>
GOOGLE_CLIENT_ID=<your-google-client-id>
GOOGLE_CLIENT_SECRET=<your-google-client-secret>
```

### Data Protection

- **Email and Google ID**: Indexed as UNIQUE to prevent duplicates
- **Soft Delete**: `is_active` flag preserves audit trail when deactivating users
- **No Plaintext Tokens**: All tokens stored encrypted
- **No Password Storage**: Authentication via Google OAuth only

## Repository Pattern

### UserRepository API

#### User Creation

```python
user_id = user_repo.create_user(
    email='user@example.com',
    google_id='google_123456',
    name='John Doe',
    profile_picture_url='https://lh3.googleusercontent.com/...',
    access_token='encrypted_access_token',
    refresh_token='encrypted_refresh_token',
    token_expires_at='2026-01-12T12:00:00'
)
```

#### User Lookups

```python
# By email (login flow)
user = user_repo.get_by_email('user@example.com')

# By Google ID (OAuth callback)
user = user_repo.get_by_google_id('google_123456')

# By ID (session management)
user = user_repo.get_by_id(user_id)
```

#### Token Management

```python
# Full token update (during OAuth login)
user_repo.update_tokens(
    user_id=user_id,
    access_token='new_encrypted_access_token',
    refresh_token='new_encrypted_refresh_token',
    token_expires_at='2026-01-12T12:00:00'
)

# Refresh access token only (preserve existing refresh_token)
user_repo.update_tokens(
    user_id=user_id,
    access_token='new_encrypted_access_token',
    refresh_token=None,  # Preserves existing
    token_expires_at='2026-01-12T12:00:00'
)
```

#### Profile Updates

```python
# Update name and/or profile picture
user_repo.update_profile(
    user_id=user_id,
    name='John Smith',
    profile_picture_url='https://...'
)
```

#### Session Tracking

```python
# Update last login timestamp after successful authentication
user_repo.update_last_login(user_id)
```

#### Account Management

```python
# Soft delete (preserve data for audit trail)
user_repo.deactivate_user(user_id)

# Reactivate deactivated account
user_repo.reactivate_user(user_id)

# List active users with pagination
active_users = user_repo.get_all_active_users(limit=50, offset=0)

# Count total active users
total = user_repo.count_active_users()
```

## Migration

### Migration File

**File**: `db/migrations/006_add_users_table.sql`

**Execution**:
```bash
python3 -m src.db.migrate
```

**Status**: Successfully executed on 2026-01-11

### Rollback Plan

If rollback is needed:

```sql
DROP TRIGGER IF EXISTS update_users_timestamp;
DROP TABLE IF EXISTS users;
DELETE FROM _migrations WHERE filename = '006_add_users_table.sql';
```

## Testing

### Test Suite

**File**: `tests/test_user_repository.py`

**Coverage**: 12 test cases covering:
- User creation and duplicate detection
- Email and Google ID lookups
- Token updates (full and selective)
- Profile updates
- Last login tracking
- User activation/deactivation
- User listing and counting

**Test Results**:
```
tests/test_user_repository.py::test_create_user PASSED
tests/test_user_repository.py::test_create_duplicate_email PASSED
tests/test_user_repository.py::test_get_by_email PASSED
tests/test_user_repository.py::test_get_by_google_id PASSED
tests/test_user_repository.py::test_update_tokens PASSED
tests/test_user_repository.py::test_update_tokens_preserve_refresh PASSED
tests/test_user_repository.py::test_update_profile PASSED
tests/test_user_repository.py::test_update_last_login PASSED
tests/test_user_repository.py::test_deactivate_user PASSED
tests/test_user_repository.py::test_reactivate_user PASSED
tests/test_user_repository.py::test_get_all_active_users PASSED
tests/test_user_repository.py::test_count_active_users PASSED

============================= 12 passed in 0.06s ==============================
```

## Future Considerations

### Phase 2: Foreign Key Relationships

After users table is integrated into the authentication flow, add user_id foreign keys to existing tables:

```sql
-- Migration: 007_add_user_foreign_keys.sql
ALTER TABLE transactions ADD COLUMN user_id INTEGER REFERENCES users(id);
ALTER TABLE parsing_sessions ADD COLUMN user_id INTEGER REFERENCES users(id);
CREATE INDEX idx_transactions_user ON transactions(user_id);
CREATE INDEX idx_parsing_sessions_user ON parsing_sessions(user_id);
```

**Impact Analysis**:
- **Transactions Table**: Add user_id to associate expenses with specific users
- **Parsing Sessions Table**: Track which user uploaded each statement
- **Data Migration**: Backfill existing records with default user_id or mark as NULL
- **Query Changes**: Add WHERE user_id = ? to all user-facing queries
- **Index Performance**: New indexes required for filtered queries

### Token Refresh Strategy

**Recommendation**: Implement background job to refresh expiring tokens

```python
# Pseudocode for token refresh job
def refresh_expiring_tokens():
    """Run daily to refresh tokens expiring within 7 days."""
    expiring_soon = datetime.now() + timedelta(days=7)
    users = get_users_with_expiring_tokens(expiring_soon)

    for user in users:
        try:
            new_access_token = refresh_google_token(user['refresh_token'])
            user_repo.update_tokens(
                user_id=user['id'],
                access_token=encrypt(new_access_token),
                refresh_token=None,  # Preserve existing
                token_expires_at=calculate_expiry()
            )
        except Exception as e:
            logger.error(f"Failed to refresh token for user {user['id']}: {e}")
```

### Token Revocation

**Recommendation**: Implement logout endpoint to clear tokens

```python
def logout_user(user_id: int):
    """Clear OAuth tokens on logout."""
    user_repo.update_tokens(
        user_id=user_id,
        access_token=None,
        refresh_token=None,
        token_expires_at=None
    )
```

### Session Management

**Recommendation**: Use JWT for session tokens (separate from Google OAuth tokens)

```python
# Generate JWT session token after OAuth login
session_token = create_jwt_token(user_id, expiry='24h')

# Validate session token on API requests
user_id = validate_jwt_token(session_token)
```

## Performance Characteristics

### Query Performance

1. **Login by email**: O(1) via UNIQUE index
2. **OAuth callback by google_id**: O(1) via UNIQUE index
3. **Session lookup by user_id**: O(1) via PRIMARY KEY
4. **List active users**: O(n) with indexed filter (is_active=1)

### Index Selectivity

- **email**: 100% unique (perfect selectivity)
- **google_id**: 100% unique (perfect selectivity)
- **is_active**: ~95% selectivity (assuming 5% deactivation rate)

### Expected Load

- **Reads**: High (every API request validates session)
- **Writes**: Low (only during login/logout/profile updates)
- **Token Updates**: Medium (periodic token refresh every ~50 minutes)

**Optimization**: Consider caching user records in Redis for session validation

```python
# Pseudocode for Redis caching
def get_user_cached(user_id: int) -> dict:
    cached = redis.get(f'user:{user_id}')
    if cached:
        return json.loads(cached)

    user = user_repo.get_by_id(user_id)
    redis.setex(f'user:{user_id}', 300, json.dumps(user))  # 5-minute TTL
    return user
```

## Operational Runbook

### User Creation Flow

1. User clicks "Sign in with Google" on frontend
2. Frontend redirects to Google OAuth consent screen
3. User approves, Google redirects to callback URL with auth code
4. Backend exchanges auth code for access_token and refresh_token
5. Backend retrieves user profile from Google API
6. Backend checks if user exists via `get_by_google_id()`
7. If new user: `create_user()` with encrypted tokens
8. If existing user: `update_tokens()` and `update_last_login()`
9. Backend generates JWT session token
10. Frontend stores session token in localStorage

### User Lookup Flow (Every API Request)

1. Frontend sends request with JWT session token in Authorization header
2. Backend validates JWT and extracts user_id
3. Backend calls `get_by_id(user_id)` (cache first, DB fallback)
4. If user is inactive: return 401 Unauthorized
5. If tokens expired: attempt refresh or prompt re-login
6. Proceed with authorized request

### Token Refresh Flow

1. Scheduled job runs every hour
2. Query users with tokens expiring within 7 days
3. For each user, decrypt refresh_token
4. Call Google OAuth token refresh endpoint
5. Encrypt new access_token
6. Update user record with new token and expiry

### Account Deactivation Flow

1. Admin or user initiates account deletion
2. Backend calls `deactivate_user(user_id)`
3. User cannot log in (is_active=0)
4. Data preserved for audit (soft delete)
5. Option to `reactivate_user()` if needed

## Files Created/Modified

### New Files

1. **db/migrations/006_add_users_table.sql**: Migration script
2. **tests/test_user_repository.py**: Comprehensive test suite
3. **docs/users_table_implementation.md**: This documentation

### Modified Files

1. **src/db/repository.py**: Added UserRepository class (480 lines)
2. **src/db/__init__.py**: Exported UserRepository

## Validation Checklist

- [x] Database schema created successfully
- [x] All indexes created and verified
- [x] Trigger for updated_at timestamp working
- [x] UserRepository implements all required methods
- [x] Comprehensive test suite written (12 tests)
- [x] All tests passing
- [x] Migration successfully executed
- [x] Documentation complete
- [x] Security considerations documented
- [x] Rollback plan documented
- [x] Git commit created with task reference

## Next Steps

1. **Phase2-Backend**: Implement OAuth endpoints (login, callback, logout)
2. **Phase3-Frontend**: Build Google Sign-In UI components
3. **Phase4-Integration**: Add user_id foreign keys to existing tables
4. **Phase5-Migration**: Backfill existing data with user associations
5. **Phase6-Testing**: End-to-end authentication flow testing

## References

- Task ID: d869c9c9
- Migration File: `db/migrations/006_add_users_table.sql`
- Repository: `src/db/repository.py` (UserRepository class)
- Tests: `tests/test_user_repository.py`
- Commit: dd29f59
