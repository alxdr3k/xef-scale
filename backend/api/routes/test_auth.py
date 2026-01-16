"""
Test authentication endpoint for E2E testing.

IMPORTANT: This endpoint should ONLY be enabled in development/test environments.
Never deploy this to production!
"""

from fastapi import APIRouter, HTTPException, status
from backend.core.security import create_access_token, create_refresh_token
from backend.core.config import settings
from backend.api.schemas import GoogleAuthResponse, UserInfo

router = APIRouter(prefix="/api/test", tags=["Test"])


@router.post("/login", response_model=GoogleAuthResponse)
async def test_login():
    """
    Create a test authentication session for E2E testing.

    SECURITY WARNING: This endpoint is for testing only and should be disabled
    in production. It creates a valid JWT token without any actual authentication.

    Returns:
        AuthResponse with access_token, refresh_token, and test user info

    Raises:
        HTTPException: 403 if not in development mode
    """
    # Safety check: only allow in development/test mode
    if not settings.ENVIRONMENT or settings.ENVIRONMENT not in ['development', 'test']:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Test authentication endpoint is only available in development/test environment"
        )

    # Create test user data using existing user id=1 from database
    # This allows the test user to access workspace memberships properly
    test_user = UserInfo(
        id="1",  # Uses existing user in database
        email="e2e-test@example.com",
        name="E2E Test User",
        picture=None
    )

    # Generate real JWT tokens (same as actual auth flow)
    token_data = {
        "sub": test_user.id,
        "email": test_user.email,
        "name": test_user.name,
        "picture": test_user.picture
    }

    access_token = create_access_token(token_data)
    refresh_token = create_refresh_token({"sub": test_user.id})

    return GoogleAuthResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        user=test_user,
        token_type="bearer"
    )
