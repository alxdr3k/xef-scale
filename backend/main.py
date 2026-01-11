"""
FastAPI application entry point.
Configures middleware, routes, and documentation.
"""

from fastapi import FastAPI, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.exceptions import RequestValidationError
import logging

from .core.config import settings
from .api.routes import auth, transactions, categories, institutions, parsing

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Create FastAPI application
app = FastAPI(
    title=settings.PROJECT_NAME,
    version=settings.VERSION,
    description="""
    # Expense Tracker REST API

    A REST API for the Expense Tracker application that automatically parses
    financial statements from Korean banks and credit cards.

    ## Authentication

    All endpoints except authentication endpoints require a valid JWT token
    in the Authorization header:

    ```
    Authorization: Bearer <your_jwt_token>
    ```

    ## Supported Institutions

    - 신한카드 (Shinhan Card)
    - 하나카드 (Hana Card)
    - 토스뱅크 (Toss Bank)
    - 토스페이 (Toss Pay)
    - 카카오뱅크 (Kakao Bank)
    - 카카오페이 (Kakao Pay)

    ## Features

    - Google OAuth authentication
    - Transaction querying with filters and pagination
    - Monthly spending summaries by category
    - Category and institution management
    - Parsing session history and debugging

    ## Implementation Status

    **Phase 1 (Current)**: API structure and documentation
    - ✅ FastAPI setup with CORS
    - ✅ JWT authentication middleware
    - ✅ Pydantic schemas for all endpoints
    - ✅ Route skeletons with comprehensive documentation
    - ✅ Swagger/OpenAPI documentation

    **Phase 2 (Next)**: Implementation
    - ⏳ Google OAuth integration
    - ⏳ Database queries using existing repositories
    - ⏳ File upload endpoint
    - ⏳ Error handling and validation
    - ⏳ Unit and integration tests
    """,
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_url=f"{settings.API_PREFIX}/openapi.json"
)

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# Exception handlers
@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    """
    Handle Pydantic validation errors with detailed error messages.

    Converts validation errors to user-friendly JSON response.
    """
    errors = []
    for error in exc.errors():
        errors.append({
            "field": ".".join(str(loc) for loc in error["loc"]),
            "message": error["msg"],
            "type": error["type"]
        })

    logger.warning(f"Validation error on {request.url}: {errors}")

    return JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        content={
            "error": "Validation error",
            "detail": errors
        }
    )


@app.exception_handler(Exception)
async def general_exception_handler(request: Request, exc: Exception):
    """
    Handle uncaught exceptions with logging and generic error response.

    Prevents internal error details from leaking to clients.
    """
    logger.error(f"Unhandled exception on {request.url}: {exc}", exc_info=True)

    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={
            "error": "Internal server error",
            "detail": "An unexpected error occurred. Please try again later."
        }
    )


# Include routers
app.include_router(auth.router, prefix=settings.API_PREFIX)
app.include_router(transactions.router, prefix=settings.API_PREFIX)
app.include_router(categories.router, prefix=settings.API_PREFIX)
app.include_router(institutions.router, prefix=settings.API_PREFIX)
app.include_router(parsing.router, prefix=settings.API_PREFIX)


# Health check endpoint
@app.get("/health", tags=["Health"])
async def health_check():
    """
    Health check endpoint for monitoring.

    Returns service status and version information.
    """
    return {
        "status": "healthy",
        "service": settings.PROJECT_NAME,
        "version": settings.VERSION
    }


# Root endpoint
@app.get("/", tags=["Root"])
async def root():
    """
    Root endpoint with API information.

    Provides links to documentation and basic API info.
    """
    return {
        "service": settings.PROJECT_NAME,
        "version": settings.VERSION,
        "documentation": "/docs",
        "openapi": f"{settings.API_PREFIX}/openapi.json"
    }


# Startup event
@app.on_event("startup")
async def startup_event():
    """
    Application startup event handler.

    Initializes resources and logs startup information.
    """
    logger.info(f"Starting {settings.PROJECT_NAME} v{settings.VERSION}")
    logger.info(f"API prefix: {settings.API_PREFIX}")
    logger.info(f"CORS allowed origins: {settings.ALLOWED_ORIGINS}")
    logger.info("Swagger documentation available at /docs")


# Shutdown event
@app.on_event("shutdown")
async def shutdown_event():
    """
    Application shutdown event handler.

    Cleans up resources gracefully.
    """
    logger.info(f"Shutting down {settings.PROJECT_NAME}")

    # TODO Phase 2: Close database connections if needed
    # Note: DatabaseConnection singleton handles this internally


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "backend.main:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
        log_level="info"
    )
