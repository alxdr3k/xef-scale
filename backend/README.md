# Expense Tracker REST API

FastAPI-based REST API for the Expense Tracker application. Provides authentication, transaction querying, and file parsing history access.

## Architecture Overview

The API follows a clean layered architecture:

```
backend/
├── main.py                 # FastAPI application entry point
├── core/                   # Core utilities
│   ├── config.py          # Environment configuration
│   └── security.py        # JWT token management
└── api/                    # API layer
    ├── dependencies.py    # Dependency injection (auth, db)
    ├── schemas.py         # Pydantic request/response models
    └── routes/            # API endpoints
        ├── auth.py        # Authentication endpoints
        ├── transactions.py # Transaction queries
        ├── categories.py   # Category management
        ├── institutions.py # Financial institution management
        └── parsing.py      # Parsing session history
```

## Features

### Authentication (Phase 1 - Skeleton)
- Google OAuth integration (Phase 2)
- JWT access tokens (30 min expiration)
- JWT refresh tokens (7 day expiration)
- Token refresh endpoint
- User info endpoint

### Transactions (Phase 1 - Skeleton)
- List transactions with filters (year, month, category, institution)
- Pagination support (max 200 items per page)
- Transaction detail by ID
- Monthly spending summary by category

### Categories & Institutions (Phase 1 - Skeleton)
- List all categories
- List all financial institutions
- Auto-created during file parsing

### Parsing Sessions (Phase 1 - Skeleton)
- List parsing session history
- View session details and statistics
- View skipped transactions with reasons

## API Documentation

### Interactive Documentation
After starting the server, visit:
- **Swagger UI**: http://localhost:8000/docs
- **ReDoc**: http://localhost:8000/redoc
- **OpenAPI JSON**: http://localhost:8000/api/openapi.json

### Health Check
```bash
curl http://localhost:8000/health
```

## Installation

### 1. Install Dependencies

```bash
# Create virtual environment (if not already done)
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install API dependencies
pip install -r requirements-api.txt
```

### 2. Environment Configuration

```bash
# Copy example environment file
cp .env.example .env

# Edit .env and set required values
# IMPORTANT: Generate secure SECRET_KEY using:
openssl rand -hex 32
```

### 3. Database Setup

The API uses the existing SQLite database from the file processing system. Ensure the database is initialized:

```bash
# Run database migrations (if needed)
python -m src.db.setup_database
```

## Running the API

### Development Mode (with auto-reload)

```bash
# Option 1: Using uvicorn directly
uvicorn backend.main:app --reload --host 0.0.0.0 --port 8000

# Option 2: Using Python module
python -m backend.main
```

### Production Mode

```bash
uvicorn backend.main:app --host 0.0.0.0 --port 8000 --workers 4
```

## API Endpoints

### Authentication

| Method | Endpoint | Description | Status |
|--------|----------|-------------|--------|
| POST | `/api/auth/google` | Google OAuth callback | Phase 2 |
| POST | `/api/auth/refresh` | Refresh access token | ✅ Phase 1 |
| POST | `/api/auth/logout` | Logout user | ✅ Phase 1 |
| GET | `/api/auth/me` | Get current user info | ✅ Phase 1 |
| GET | `/api/auth/status` | Check auth status | ✅ Phase 1 |

### Transactions

| Method | Endpoint | Description | Status |
|--------|----------|-------------|--------|
| GET | `/api/transactions` | List transactions (filtered) | Phase 2 |
| GET | `/api/transactions/:id` | Get transaction detail | Phase 2 |
| GET | `/api/transactions/summary/monthly` | Monthly spending summary | Phase 2 |

### Categories

| Method | Endpoint | Description | Status |
|--------|----------|-------------|--------|
| GET | `/api/categories` | List all categories | Phase 2 |

### Institutions

| Method | Endpoint | Description | Status |
|--------|----------|-------------|--------|
| GET | `/api/institutions` | List all institutions | Phase 2 |

### Parsing Sessions

| Method | Endpoint | Description | Status |
|--------|----------|-------------|--------|
| GET | `/api/parsing-sessions` | List parsing sessions | Phase 2 |
| GET | `/api/parsing-sessions/:id` | Get session detail | Phase 2 |
| GET | `/api/parsing-sessions/:id/skipped` | Get skipped transactions | Phase 2 |

## Authentication Flow

### Phase 2: Google OAuth
1. Frontend redirects to Google OAuth consent screen
2. User approves, Google redirects back with authorization code
3. Frontend sends code to `/api/auth/google`
4. Backend exchanges code for user info with Google
5. Backend generates JWT tokens and returns to frontend
6. Frontend stores tokens (localStorage or httpOnly cookie)
7. Frontend includes token in Authorization header for subsequent requests

### Token Refresh
1. Access token expires after 30 minutes
2. Frontend sends refresh token to `/api/auth/refresh`
3. Backend validates refresh token and issues new access/refresh tokens
4. Frontend updates stored tokens

## Request/Response Examples

### Get Transactions (Phase 2)

**Request:**
```bash
curl -X GET "http://localhost:8000/api/transactions?year=2025&month=9&category=식비&page=1&page_size=50" \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIs..."
```

**Response:**
```json
{
  "transactions": [
    {
      "id": 1,
      "date": "2025.09.13",
      "category": "식비",
      "merchant_name": "스타벅스",
      "amount": 5000,
      "institution": "하나카드",
      "transaction_year": 2025,
      "transaction_month": 9,
      "created_at": "2025-09-13T12:00:00"
    }
  ],
  "total": 150,
  "page": 1,
  "page_size": 50
}
```

### Monthly Summary (Phase 2)

**Request:**
```bash
curl -X GET "http://localhost:8000/api/transactions/summary/monthly?year=2025&month=9" \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIs..."
```

**Response:**
```json
{
  "year": 2025,
  "month": 9,
  "categories": [
    {"category": "식비", "total": 450000},
    {"category": "교통", "total": 120000},
    {"category": "통신", "total": 80000}
  ],
  "total_spending": 650000
}
```

## Error Handling

The API returns consistent error responses:

### Validation Error (422)
```json
{
  "error": "Validation error",
  "detail": [
    {
      "field": "body.month",
      "message": "Month must be between 1 and 12",
      "type": "value_error"
    }
  ]
}
```

### Authentication Error (401)
```json
{
  "error": "Invalid or expired token",
  "detail": "Token signature verification failed"
}
```

### Not Found Error (404)
```json
{
  "error": "Transaction not found",
  "detail": "No transaction with ID 999"
}
```

## Security Considerations

### Production Deployment Checklist

- [ ] Generate strong SECRET_KEY (32+ random bytes)
- [ ] Set appropriate ALLOWED_ORIGINS (no wildcards)
- [ ] Use HTTPS in production
- [ ] Enable rate limiting (via reverse proxy or middleware)
- [ ] Set up proper logging and monitoring
- [ ] Configure GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET
- [ ] Use environment variables (not .env file)
- [ ] Enable database backups
- [ ] Set up proper error tracking (Sentry, etc.)

### JWT Best Practices

- Access tokens are short-lived (30 min)
- Refresh tokens are longer-lived (7 days)
- Tokens are stateless (no server-side session storage)
- Token payload includes: user_id, email, name, picture
- Tokens are signed with HS256 algorithm
- Phase 2: Consider implementing token blacklist for logout

## Testing

### Manual Testing with curl

```bash
# Health check
curl http://localhost:8000/health

# Get API documentation
curl http://localhost:8000/

# Refresh token (Phase 1 working)
curl -X POST "http://localhost:8000/api/auth/refresh" \
  -H "Content-Type: application/json" \
  -d '{"refresh_token": "your_refresh_token"}'
```

### Testing with Swagger UI

1. Start the API server
2. Open http://localhost:8000/docs
3. Click "Authorize" button
4. Enter Bearer token: `Bearer your_jwt_token`
5. Try out different endpoints

## Phase 2 Implementation Checklist

### Google OAuth Integration
- [ ] Implement Google OAuth client configuration
- [ ] Exchange authorization code for access token
- [ ] Fetch user info from Google API
- [ ] Create/update user in database
- [ ] Generate JWT tokens with user data

### Database Queries
- [ ] Implement transaction filtering and pagination
- [ ] Implement monthly summary aggregation
- [ ] Implement category listing
- [ ] Implement institution listing
- [ ] Implement parsing session queries

### Additional Features
- [ ] File upload endpoint
- [ ] Error handling improvements
- [ ] Input validation enhancements
- [ ] Rate limiting middleware
- [ ] Comprehensive logging

### Testing
- [ ] Unit tests for security functions
- [ ] Unit tests for schemas
- [ ] Integration tests for API endpoints
- [ ] Authentication flow tests
- [ ] Database query tests

## Troubleshooting

### Import Errors

If you get import errors like `ModuleNotFoundError: No module named 'backend'`:

```bash
# Run from project root
cd /Users/yngn/ws/expense-tracker
python -m backend.main
```

### Database Connection Issues

If database connection fails:

```bash
# Check database exists
ls -la data/expense_tracker.db

# Verify database schema
sqlite3 data/expense_tracker.db ".schema"
```

### CORS Issues

If frontend can't connect:

1. Check ALLOWED_ORIGINS in .env
2. Verify frontend origin matches exactly
3. Check browser console for CORS errors

## Contributing

When adding new endpoints:

1. Define Pydantic schemas in `api/schemas.py`
2. Create route handler in appropriate `api/routes/*.py` file
3. Add comprehensive docstrings
4. Update this README with new endpoints
5. Test manually and add unit tests

## License

This project is part of the Expense Tracker application.
