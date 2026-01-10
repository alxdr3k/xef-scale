"""
Authentication routes for Google OAuth and JWT token management.
Handles login, token refresh, and user information.
"""

from fastapi import APIRouter, HTTPException, status, Depends
from backend.api.schemas import (
    TokenResponse,
    UserInfo,
    GoogleAuthRequest,
    ErrorResponse
)
from backend.api.dependencies import get_current_user, get_optional_user
from backend.core.security import create_access_token, create_refresh_token, verify_token
from backend.core.config import settings

router = APIRouter(prefix="/auth", tags=["Authentication"])


@router.post(
    "/google",
    response_model=TokenResponse,
    responses={
        401: {"model": ErrorResponse, "description": "Invalid authorization code"},
        500: {"model": ErrorResponse, "description": "Google OAuth error"}
    }
)
async def google_auth(request: GoogleAuthRequest):
    """
    Handle Google OAuth callback and create JWT tokens.

    Exchanges Google authorization code for user information and generates
    access and refresh tokens for subsequent API calls.

    **Implementation Status**: Skeleton - Phase 2 will implement actual Google OAuth flow.

    Args:
        request: GoogleAuthRequest with authorization code from Google

    Returns:
        TokenResponse with access_token, refresh_token, and token_type

    Raises:
        HTTPException: 401 if authorization code is invalid
        HTTPException: 500 if Google API call fails

    Notes:
        - Phase 2 will implement actual Google OAuth integration
        - Will exchange code for user info via Google API
        - Will create/update user in database
        - Will generate JWT tokens with user data
    """
    # TODO Phase 2: Implement Google OAuth flow
    # 1. Exchange authorization code for access token with Google
    # 2. Fetch user info from Google (email, name, picture)
    # 3. Create/update user in database
    # 4. Generate JWT tokens with user data

    raise HTTPException(
        status_code=status.HTTP_501_NOT_IMPLEMENTED,
        detail="Google OAuth integration will be implemented in Phase 2"
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
    status_code=status.HTTP_204_NO_CONTENT,
    responses={
        204: {"description": "Successfully logged out"},
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
        204 No Content on success

    Notes:
        - Client should delete stored access and refresh tokens
        - Future: Implement token blacklist for server-side invalidation
        - Future: Store refresh tokens in database for revocation
    """
    # TODO Phase 2: Implement server-side token invalidation
    # Option 1: Add tokens to blacklist with expiration
    # Option 2: Store refresh tokens in DB and mark as revoked
    # For now, client-side token deletion is sufficient
    return None


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
