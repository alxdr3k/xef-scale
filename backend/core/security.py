"""
JWT token generation and validation for authentication.
Provides utility functions for secure token management.
"""

from datetime import datetime, timedelta
from typing import Optional, Dict, Any
from jose import JWTError, jwt
from passlib.context import CryptContext
from backend.core.config import settings


# Password hashing context (not used for Google OAuth, but useful for future)
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def create_access_token(data: Dict[str, Any], expires_delta: Optional[timedelta] = None) -> str:
    """
    Create a JWT access token with expiration.

    Encodes user data (typically user_id and email) into a signed JWT token
    with configurable expiration time.

    Args:
        data: Payload to encode in token (e.g., {"sub": user_id, "email": user_email})
        expires_delta: Optional custom expiration timedelta (default: from settings)

    Returns:
        str: Encoded JWT token

    Examples:
        >>> token = create_access_token({"sub": "user123", "email": "user@example.com"})
        >>> print(token[:20])
        'eyJhbGciOiJIUzI1NiIs...'

    Notes:
        - Token includes "exp" claim for expiration validation
        - Uses HS256 algorithm (symmetric signing)
        - Default expiration from settings.ACCESS_TOKEN_EXPIRE_MINUTES
        - Token should be sent in Authorization header: "Bearer {token}"
    """
    to_encode = data.copy()

    # Set expiration time
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)

    to_encode.update({"exp": expire})

    # Encode and sign token
    encoded_jwt = jwt.encode(to_encode, settings.SECRET_KEY, algorithm=settings.ALGORITHM)
    return encoded_jwt


def create_refresh_token(data: Dict[str, Any]) -> str:
    """
    Create a JWT refresh token with longer expiration.

    Refresh tokens are used to obtain new access tokens without re-authentication.
    They have longer lifetime than access tokens.

    Args:
        data: Payload to encode in token (e.g., {"sub": user_id})

    Returns:
        str: Encoded JWT refresh token

    Examples:
        >>> refresh_token = create_refresh_token({"sub": "user123"})
        >>> print(refresh_token[:20])
        'eyJhbGciOiJIUzI1NiIs...'

    Notes:
        - Longer expiration than access tokens (default: 7 days)
        - Should be stored securely on client (httpOnly cookie recommended)
        - Used to obtain new access token when current one expires
    """
    expires_delta = timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)
    return create_access_token(data, expires_delta)


def verify_token(token: str) -> Optional[Dict[str, Any]]:
    """
    Verify and decode a JWT token.

    Validates token signature and expiration, returns payload if valid.

    Args:
        token: JWT token string to verify

    Returns:
        Dict with token payload if valid, None if invalid/expired

    Examples:
        >>> token = create_access_token({"sub": "user123"})
        >>> payload = verify_token(token)
        >>> print(payload["sub"])
        'user123'

        >>> # Invalid token
        >>> payload = verify_token("invalid_token")
        >>> print(payload)
        None

    Notes:
        - Returns None on any validation error (signature, expiration, format)
        - Does not raise exceptions for invalid tokens
        - Caller should check for None and handle authentication failure
    """
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        return payload
    except JWTError:
        return None


def hash_password(password: str) -> str:
    """
    Hash a password using bcrypt.

    Not currently used (Google OAuth flow), but provided for future
    password-based authentication or API keys.

    Args:
        password: Plain text password to hash

    Returns:
        str: Bcrypt hashed password

    Examples:
        >>> hashed = hash_password("my_secure_password")
        >>> print(hashed[:7])
        '$2b$12$'

    Notes:
        - Uses bcrypt with automatic salt generation
        - Computationally expensive (prevents brute force)
        - Hash is safe to store in database
    """
    return pwd_context.hash(password)


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """
    Verify a password against its hash.

    Not currently used (Google OAuth flow), but provided for future
    password-based authentication.

    Args:
        plain_password: Plain text password to verify
        hashed_password: Bcrypt hashed password from database

    Returns:
        bool: True if password matches, False otherwise

    Examples:
        >>> hashed = hash_password("my_password")
        >>> verify_password("my_password", hashed)
        True
        >>> verify_password("wrong_password", hashed)
        False

    Notes:
        - Constant-time comparison (prevents timing attacks)
        - Returns False for any error (invalid hash format, etc.)
    """
    return pwd_context.verify(plain_password, hashed_password)
