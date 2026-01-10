"""
FastAPI dependency injection for authentication and database access.
Provides reusable dependencies for route handlers.
"""

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from typing import Optional
import sqlite3

from backend.core.security import verify_token
from backend.api.schemas import UserInfo
from src.db.connection import DatabaseConnection


# Security scheme for JWT bearer tokens
security = HTTPBearer()


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security)
) -> UserInfo:
    """
    Dependency to extract and validate current user from JWT token.

    Validates the JWT token from Authorization header and returns user information.
    Raises HTTP 401 if token is invalid or expired.

    Args:
        credentials: HTTP bearer credentials from Authorization header

    Returns:
        UserInfo: Current authenticated user information

    Raises:
        HTTPException: 401 if token is invalid, expired, or missing required fields

    Examples:
        >>> # In route handler
        >>> @router.get("/me")
        >>> async def get_me(current_user: UserInfo = Depends(get_current_user)):
        ...     return current_user

    Notes:
        - Token should be in format: "Bearer {jwt_token}"
        - Automatically extracts token from Authorization header
        - Validates signature and expiration
        - Returns user data from token payload
    """
    token = credentials.credentials

    # Verify and decode token
    payload = verify_token(token)
    if payload is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
            headers={"WWW-Authenticate": "Bearer"},
        )

    # Extract user information from payload
    user_id = payload.get("sub")
    email = payload.get("email")

    if not user_id or not email:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token payload",
            headers={"WWW-Authenticate": "Bearer"},
        )

    return UserInfo(
        id=user_id,
        email=email,
        name=payload.get("name"),
        picture=payload.get("picture")
    )


async def get_optional_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(
        HTTPBearer(auto_error=False)
    )
) -> Optional[UserInfo]:
    """
    Dependency to optionally extract current user from JWT token.

    Similar to get_current_user, but doesn't raise error if token is missing.
    Useful for endpoints that have different behavior for authenticated vs anonymous users.

    Args:
        credentials: Optional HTTP bearer credentials

    Returns:
        UserInfo if valid token provided, None otherwise

    Examples:
        >>> # In route handler
        >>> @router.get("/public")
        >>> async def public_endpoint(user: Optional[UserInfo] = Depends(get_optional_user)):
        ...     if user:
        ...         return f"Hello {user.email}"
        ...     return "Hello anonymous"

    Notes:
        - Returns None if no token provided or token is invalid
        - Does not raise authentication errors
        - Useful for public endpoints with optional authentication
    """
    if credentials is None:
        return None

    token = credentials.credentials
    payload = verify_token(token)

    if payload is None:
        return None

    user_id = payload.get("sub")
    email = payload.get("email")

    if not user_id or not email:
        return None

    return UserInfo(
        id=user_id,
        email=email,
        name=payload.get("name"),
        picture=payload.get("picture")
    )


def get_db() -> sqlite3.Connection:
    """
    Dependency to get database connection.

    Provides singleton database connection for repository operations.
    Uses existing DatabaseConnection singleton pattern.

    Returns:
        sqlite3.Connection: Database connection with Row factory

    Examples:
        >>> # In route handler
        >>> @router.get("/transactions")
        >>> async def get_transactions(db: sqlite3.Connection = Depends(get_db)):
        ...     cursor = db.execute("SELECT * FROM transactions")
        ...     return cursor.fetchall()

    Notes:
        - Returns singleton connection (thread-safe)
        - Connection is already configured with:
            - WAL mode for concurrent reads
            - Foreign key constraints enabled
            - Row factory for dict-like access
        - No need to close connection (managed by singleton)
    """
    return DatabaseConnection.get_instance()


async def verify_api_access(
    current_user: UserInfo = Depends(get_current_user)
) -> UserInfo:
    """
    Dependency to verify user has API access.

    Currently just validates authentication, but can be extended
    to check user permissions, subscription status, rate limits, etc.

    Args:
        current_user: Current authenticated user from get_current_user

    Returns:
        UserInfo: Validated user with API access

    Raises:
        HTTPException: 403 if user doesn't have API access

    Examples:
        >>> # In route handler
        >>> @router.post("/admin/delete")
        >>> async def admin_delete(user: UserInfo = Depends(verify_api_access)):
        ...     # Only accessible to authenticated users with API access
        ...     return {"status": "deleted"}

    Notes:
        - Currently passes through all authenticated users
        - Can be extended to implement role-based access control
        - Can check database for user permissions/roles
        - Can implement rate limiting per user
    """
    # Future: Check database for user roles, permissions, etc.
    # For now, all authenticated users have API access
    return current_user
