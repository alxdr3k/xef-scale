# Google OAuth Authentication Implementation

## Overview

This document describes the Google OAuth authentication implementation for Phase 2-API.

## Task ID: 3947a9bf

## Implementation Details

### Endpoints Implemented

#### 1. POST /api/auth/google
Authenticates users via Google ID token verification.

**Request:**
```json
{
  "credential": "eyJhbGciOiJSUzI1NiIsImtpZCI6..." // Google ID token
}
```

**Response:**
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6...",
  "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6...",
  "token_type": "bearer",
  "user": {
    "id": "1",
    "email": "user@example.com",
    "name": "John Doe",
    "picture": "https://lh3.googleusercontent.com/..."
  }
}
```

**Flow:**
1. Frontend obtains Google ID token via Google Sign-In JavaScript library
2. Frontend sends token to `/api/auth/google`
3. Backend verifies token with Google's public keys
4. Backend checks if user exists by `google_id`
5. If new user: creates account in database
6. If existing user: updates `last_login_at`
7. Generates JWT access token (30 min) and refresh token (7 days)
8. Returns tokens + user info

**Error Responses:**
- 401: Invalid Google ID token
- 500: Database error or authentication failure

#### 2. GET /api/auth/me
Returns current authenticated user information from JWT token.

**Headers:**
```
Authorization: Bearer <access_token>
```

**Response:**
```json
{
  "id": "1",
  "email": "user@example.com",
  "name": "John Doe",
  "picture": "https://lh3.googleusercontent.com/..."
}
```

**Error Responses:**
- 401: Invalid or expired token

#### 3. POST /api/auth/logout
Logs out current user (client-side token deletion).

**Headers:**
```
Authorization: Bearer <access_token>
```

**Response:**
```json
{
  "message": "Logged out successfully"
}
```

**Note:** JWT tokens are stateless, so logout is client-side only. The client should delete stored tokens.

**Error Responses:**
- 401: Not authenticated

## Configuration

### Environment Variables

Set these in `.env` file (copy from `.env.example`):

```bash
# Google OAuth Client ID from Google Cloud Console
GOOGLE_CLIENT_ID=your_client_id.apps.googleusercontent.com

# JWT Secret Key (generate with: openssl rand -hex 32)
SECRET_KEY=your_secret_key_here

# Token Expiration
ACCESS_TOKEN_EXPIRE_MINUTES=30
REFRESH_TOKEN_EXPIRE_DAYS=7
```

### Getting Google Client ID

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select existing
3. Enable Google+ API
4. Create OAuth 2.0 credentials
5. Add authorized JavaScript origins:
   - `http://localhost:3000` (React dev)
   - `http://localhost:5173` (Vite dev)
6. Copy Client ID to `.env`

## Database Schema

### Users Table (Migration 006)

The authentication uses the `users` table created in Phase 1:

```sql
CREATE TABLE users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    email TEXT UNIQUE NOT NULL,
    google_id TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    profile_picture_url TEXT,
    is_active INTEGER DEFAULT 1,
    created_at TEXT NOT NULL,
    updated_at TEXT,
    last_login_at TEXT
);
```

## Repository Usage

The implementation uses `UserRepository` from `src/db/repository.py`:

- `get_by_google_id(google_id)`: Lookup existing user
- `create_user(email, google_id, name, profile_picture_url)`: Create new user
- `update_last_login(user_id)`: Update login timestamp

## Security Considerations

1. **Google ID Token Verification**: Backend verifies token signature with Google's public keys
2. **JWT Tokens**: Signed with HS256 algorithm using SECRET_KEY
3. **Token Payload**: Contains user_id (sub), email, name, picture
4. **Token Expiration**: Access tokens expire in 30 minutes, refresh tokens in 7 days
5. **HTTPS Required**: In production, use HTTPS for all auth endpoints
6. **CORS**: Configure allowed origins for frontend

## Testing

### Manual Testing with curl

**Note:** You need a valid Google ID token. Get one from:
- Google OAuth Playground: https://developers.google.com/oauthplayground/
- Or implement Google Sign-In button in frontend

```bash
# 1. Authenticate with Google
curl -X POST http://localhost:8000/api/auth/google \
  -H "Content-Type: application/json" \
  -d '{
    "credential": "YOUR_GOOGLE_ID_TOKEN"
  }'

# 2. Get current user info
curl -X GET http://localhost:8000/api/auth/me \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"

# 3. Logout
curl -X POST http://localhost:8000/api/auth/logout \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"
```

### Frontend Integration Example

```javascript
// 1. Initialize Google Sign-In
google.accounts.id.initialize({
  client_id: 'YOUR_CLIENT_ID.apps.googleusercontent.com',
  callback: handleCredentialResponse
});

// 2. Handle Google Sign-In response
async function handleCredentialResponse(response) {
  const res = await fetch('http://localhost:8000/api/auth/google', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ credential: response.credential })
  });

  const data = await res.json();

  // Store tokens
  localStorage.setItem('access_token', data.access_token);
  localStorage.setItem('refresh_token', data.refresh_token);

  // Store user info
  localStorage.setItem('user', JSON.stringify(data.user));
}

// 3. Make authenticated requests
async function fetchUserData() {
  const token = localStorage.getItem('access_token');

  const res = await fetch('http://localhost:8000/api/auth/me', {
    headers: { 'Authorization': `Bearer ${token}` }
  });

  return await res.json();
}

// 4. Logout
async function logout() {
  const token = localStorage.getItem('access_token');

  await fetch('http://localhost:8000/api/auth/logout', {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${token}` }
  });

  // Clear local storage
  localStorage.removeItem('access_token');
  localStorage.removeItem('refresh_token');
  localStorage.removeItem('user');
}
```

## Files Modified

1. **backend/api/schemas.py**
   - Updated `GoogleAuthRequest` to use `credential` field
   - Added `GoogleAuthResponse` schema
   - Added `LogoutResponse` schema

2. **backend/api/routes/auth.py**
   - Implemented `/api/auth/google` endpoint
   - Updated `/api/auth/logout` to return JSON response
   - Added Google ID token verification
   - Integrated UserRepository for user management
   - Added comprehensive error handling

3. **requirements-api.txt**
   - Already includes `google-auth>=2.27.0` (no changes needed)

## Dependencies

All required dependencies are already in `requirements-api.txt`:

```
google-auth>=2.27.0
google-auth-oauthlib>=1.2.0
google-auth-httplib2>=0.2.0
python-jose[cryptography]>=3.3.0
passlib[bcrypt]>=1.7.4
```

## Next Steps (Phase 2+)

1. **Token Refresh Endpoint**: Already implemented in `/api/auth/refresh`
2. **Token Blacklist**: Add Redis/database-backed token invalidation
3. **Refresh Token Rotation**: Rotate refresh tokens on each use
4. **Rate Limiting**: Add rate limiting to auth endpoints
5. **Audit Logging**: Log all authentication events
6. **Multi-factor Authentication**: Add optional MFA
7. **Session Management**: Track active sessions per user

## Troubleshooting

### "Invalid Google ID token" Error

- Verify `GOOGLE_CLIENT_ID` in `.env` matches your Google Cloud Console
- Ensure token is fresh (Google ID tokens expire quickly)
- Check token was issued for your client ID

### "User account creation failed" Error

- Check database permissions
- Verify database schema is up to date (migration 006)
- Check for duplicate email/google_id conflicts

### CORS Issues

- Add frontend origin to `ALLOWED_ORIGINS` in `.env`
- Verify CORS middleware is configured in main.py

## Implementation Notes

- **Stateless JWT**: Tokens are self-contained, no server-side session storage
- **User Lookup**: Uses `google_id` as primary lookup key (indexed)
- **Profile Updates**: User name/picture updated on each login
- **Soft Delete**: Users can be deactivated via `is_active` flag
- **Timezone**: All timestamps in ISO 8601 format (UTC)
