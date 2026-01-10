"""
FastAPI application configuration.
Centralizes environment variables and application settings.
"""

from pydantic_settings import BaseSettings
from typing import List


class Settings(BaseSettings):
    """
    Application settings loaded from environment variables.

    Attributes:
        PROJECT_NAME: Application name for API documentation
        VERSION: API version string
        API_PREFIX: URL prefix for all API routes
        SECRET_KEY: Secret key for JWT token signing (MUST be set in production)
        ALGORITHM: JWT signing algorithm
        ACCESS_TOKEN_EXPIRE_MINUTES: JWT access token lifetime
        REFRESH_TOKEN_EXPIRE_DAYS: JWT refresh token lifetime
        ALLOWED_ORIGINS: CORS allowed origins for frontend
        GOOGLE_CLIENT_ID: Google OAuth client ID
        GOOGLE_CLIENT_SECRET: Google OAuth client secret
        GOOGLE_REDIRECT_URI: Google OAuth redirect URI

    Examples:
        >>> settings = Settings()
        >>> print(settings.PROJECT_NAME)
        'Expense Tracker API'

    Notes:
        - Uses Pydantic BaseSettings for automatic env var loading
        - Supports .env file via python-dotenv integration
        - Secret key MUST be changed in production
        - CORS origins should be restricted in production
    """

    # Application metadata
    PROJECT_NAME: str = "Expense Tracker API"
    VERSION: str = "1.0.0"
    API_PREFIX: str = "/api"

    # Security settings
    SECRET_KEY: str = "CHANGE_THIS_IN_PRODUCTION_USE_openssl_rand_hex_32"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    REFRESH_TOKEN_EXPIRE_DAYS: int = 7

    # CORS settings
    ALLOWED_ORIGINS: List[str] = [
        "http://localhost:3000",  # React dev server
        "http://localhost:5173",  # Vite dev server
        "http://localhost:8080",  # Alternative frontend port
    ]

    # Google OAuth settings
    GOOGLE_CLIENT_ID: str = ""
    GOOGLE_CLIENT_SECRET: str = ""
    GOOGLE_REDIRECT_URI: str = "http://localhost:8000/api/auth/google/callback"

    class Config:
        env_file = ".env"
        case_sensitive = True


# Global settings instance
settings = Settings()
