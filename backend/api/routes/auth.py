"""
Authentication routes for Google OAuth and JWT token management.
Handles login, token refresh, and user information.
"""

from fastapi import APIRouter, HTTPException, status, Depends
from backend.api.schemas import (
    TokenResponse,
    UserInfo,
    GoogleAuthRequest,
    GoogleAuthResponse,
    LogoutResponse,
    ErrorResponse
)
from backend.api.dependencies import get_current_user, get_optional_user, get_db
from backend.core.security import create_access_token, create_refresh_token, verify_token
from backend.core.config import settings
from src.db.repository import UserRepository
from google.auth.transport import requests
from google.oauth2 import id_token
import logging
import sqlite3

router = APIRouter(prefix="/auth", tags=["Authentication"])
logger = logging.getLogger(__name__)


@router.post(
    "/google",
    response_model=GoogleAuthResponse,
    responses={
        401: {"model": ErrorResponse, "description": "Invalid Google ID token"},
        500: {"model": ErrorResponse, "description": "Google OAuth error"}
    }
)
async def google_auth(request: GoogleAuthRequest, db: sqlite3.Connection = Depends(get_db)):
    """
    Handle Google OAuth authentication and create JWT tokens.

    Verifies Google ID token, creates or retrieves user from database,
    and generates access and refresh tokens for subsequent API calls.

    Args:
        request: GoogleAuthRequest with Google ID token (credential)
        db: Database connection from dependency injection

    Returns:
        GoogleAuthResponse with access_token, refresh_token, token_type, and user info

    Raises:
        HTTPException: 401 if Google ID token is invalid
        HTTPException: 500 if database or Google API call fails

    Notes:
        - Verifies Google ID token with Google's public keys
        - Creates new user if not exists, updates last_login if exists
        - Generates JWT tokens with user data (sub, email, name, picture)
        - Google ID is stored for future lookups
    """
    try:
        # Verify Google ID token
        idinfo = id_token.verify_oauth2_token(
            request.credential,
            requests.Request(),
            settings.GOOGLE_CLIENT_ID
        )

        # Extract user information from token
        google_id = idinfo['sub']
        email = idinfo['email']
        name = idinfo.get('name')
        picture = idinfo.get('picture')

        logger.info(f"Google auth successful for email: {email}")

        # Initialize UserRepository
        user_repo = UserRepository(db)

        # Check if user exists by google_id
        user = user_repo.get_by_google_id(google_id)

        if user:
            # User exists - update last login
            user_repo.update_last_login(user['id'])
            logger.info(f"Existing user logged in: {email} (user_id={user['id']})")
        else:
            # New user - create account
            user_id = user_repo.create_user(
                email=email,
                google_id=google_id,
                name=name,
                profile_picture_url=picture
            )
            user = user_repo.get_by_id(user_id)
            logger.info(f"New user created: {email} (user_id={user_id})")

        # Prepare JWT payload
        user_data = {
            "sub": str(user['id']),  # User ID as subject
            "email": user['email'],
            "name": user['name'],
            "picture": user['profile_picture_url']
        }

        # Generate JWT tokens
        access_token = create_access_token(user_data)
        refresh_token = create_refresh_token({"sub": str(user['id'])})

        # Return response with user info
        return GoogleAuthResponse(
            access_token=access_token,
            refresh_token=refresh_token,
            token_type="bearer",
            user=UserInfo(
                id=str(user['id']),
                email=user['email'],
                name=user['name'],
                picture=user['profile_picture_url']
            )
        )

    except ValueError as e:
        # Invalid token or verification failed
        logger.error(f"Google ID token verification failed: {e}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid Google ID token"
        )
    except sqlite3.IntegrityError as e:
        # Database constraint violation (e.g., duplicate email)
        logger.error(f"Database integrity error during user creation: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="User account creation failed"
        )
    except Exception as e:
        # Catch-all for unexpected errors
        logger.error(f"Unexpected error during Google authentication: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Authentication failed"
        )


@router.post(
    "/refresh",
    response_model=TokenResponse,
    responses={
        401: {"model": ErrorResponse, "description": "Invalid or expired refresh token"}
    }
)
async def refresh_token(refresh_token: str):
    """
    Refresh access token using refresh token.

    Validates refresh token and generates new access and refresh tokens.
    Allows users to stay authenticated without re-logging in.

    Args:
        refresh_token: JWT refresh token from previous authentication

    Returns:
        TokenResponse with new access_token and refresh_token

    Raises:
        HTTPException: 401 if refresh token is invalid or expired

    Examples:
        >>> # Request body
        >>> {
        ...     "refresh_token": "eyJhbGciOiJIUzI1NiIs..."
        ... }

    Notes:
        - Refresh token must be valid and not expired
        - Returns new access and refresh tokens
        - Old refresh token should be discarded
        - Client should update stored tokens
    """
    payload = verify_token(refresh_token)

    if payload is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired refresh token",
            headers={"WWW-Authenticate": "Bearer"},
        )

    # Extract user data from refresh token
    user_data = {
        "sub": payload.get("sub"),
        "email": payload.get("email"),
        "name": payload.get("name"),
        "picture": payload.get("picture")
    }

    # Generate new tokens
    new_access_token = create_access_token(user_data)
    new_refresh_token = create_refresh_token({"sub": user_data["sub"]})

    return TokenResponse(
        access_token=new_access_token,
        refresh_token=new_refresh_token,
        token_type="bearer"
    )


@router.post(
    "/logout",
    response_model=LogoutResponse,
    responses={
        200: {"model": LogoutResponse, "description": "Successfully logged out"},
        401: {"model": ErrorResponse, "description": "Not authenticated"}
    }
)
async def logout(current_user: UserInfo = Depends(get_current_user)):
    """
    Logout current user.

    Invalidates current session. Client should discard access and refresh tokens.

    **Note**: JWT tokens are stateless, so server-side invalidation requires
    additional infrastructure (token blacklist, etc.). For now, client-side
    token deletion is sufficient.

    Args:
        current_user: Current authenticated user from JWT token

    Returns:
        LogoutResponse with success message

    Notes:
        - Client should delete stored access and refresh tokens
        - Future: Implement token blacklist for server-side invalidation
        - Future: Store refresh tokens in database for revocation
    """
    # TODO Phase 2+: Implement server-side token invalidation
    # Option 1: Add tokens to blacklist with expiration
    # Option 2: Store refresh tokens in DB and mark as revoked
    # For now, client-side token deletion is sufficient

    logger.info(f"User logged out: {current_user.email} (user_id={current_user.id})")
    return LogoutResponse(message="Logged out successfully")


@router.get(
    "/me",
    response_model=UserInfo,
    responses={
        401: {"model": ErrorResponse, "description": "Not authenticated"}
    }
)
async def get_current_user_info(current_user: UserInfo = Depends(get_current_user)):
    """
    Get current authenticated user information.

    Returns user information from JWT token. Useful for client-side
    authentication state management.

    Args:
        current_user: Current authenticated user from JWT token

    Returns:
        UserInfo with id, email, name, and picture

    Examples:
        >>> # Response
        >>> {
        ...     "id": "google_12345",
        ...     "email": "user@example.com",
        ...     "name": "John Doe",
        ...     "picture": "https://..."
        ... }

    Notes:
        - Requires valid access token in Authorization header
        - Returns user data from token (no database query)
        - Useful for checking authentication status
        - Can be used to populate user profile UI
    """
    return current_user


@router.get(
    "/status",
    response_model=dict,
    responses={
        200: {"description": "Authentication status"}
    }
)
async def auth_status(user: UserInfo = Depends(get_optional_user)):
    """
    Check authentication status without requiring authentication.

    Returns whether user is authenticated and basic user info if available.
    Useful for public pages that want to show personalized content for logged-in users.

    Args:
        user: Optional user from JWT token (None if not authenticated)

    Returns:
        Dict with authenticated status and user info if available

    Examples:
        >>> # Authenticated response
        >>> {
        ...     "authenticated": true,
        ...     "user": {
        ...         "id": "google_12345",
        ...         "email": "user@example.com",
        ...         "name": "John Doe"
        ...     }
        ... }

        >>> # Anonymous response
        >>> {
        ...     "authenticated": false,
        ...     "user": null
        ... }

    Notes:
        - Does not require authentication (public endpoint)
        - Returns user info if valid token provided
        - Useful for conditional UI rendering
    """
    return {
        "authenticated": user is not None,
        "user": user
    }
