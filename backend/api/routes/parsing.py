"""
Parsing session routes for viewing file processing history.
Provides read-only access to parsing sessions and skipped transactions.
"""

from fastapi import APIRouter, Depends, HTTPException, status, Query
from typing import List
import sqlite3

from backend.api.schemas import (
    ParsingSessionResponse,
    ParsingSessionListResponse,
    SkippedTransactionResponse,
    ErrorResponse,
    UserInfo
)
from backend.api.dependencies import get_current_user, get_db
from src.db.repository import ParsingSessionRepository, SkippedTransactionRepository

router = APIRouter(prefix="/parsing-sessions", tags=["Parsing Sessions"])


@router.get(
    "",
    response_model=ParsingSessionListResponse,
    responses={
        401: {"model": ErrorResponse, "description": "Not authenticated"}
    }
)
async def get_parsing_sessions(
    page: int = Query(1, ge=1, description="Page number (1-indexed)"),
    page_size: int = Query(50, ge=1, le=200, description="Items per page"),
    db: sqlite3.Connection = Depends(get_db),
    current_user: UserInfo = Depends(get_current_user)
):
    """
    Get paginated list of parsing sessions.

    Returns parsing sessions with file details and processing statistics,
    sorted by start time (most recent first).

    **Implementation Status**: Skeleton - Phase 2 will implement actual query.

    Args:
        page: Page number for pagination (1-indexed)
        page_size: Number of items per page (max 200)
        db: Database connection from dependency
        current_user: Current authenticated user

    Returns:
        ParsingSessionListResponse with sessions array, total count, and pagination info

    Examples:
        >>> # Get recent parsing sessions
        >>> GET /api/parsing-sessions?page=1&page_size=20

        >>> # Response
        >>> {
        ...     "sessions": [
        ...         {
        ...             "id": 1,
        ...             "file_id": 1,
        ...             "parser_type": "HANA",
        ...             "started_at": "2025-01-10T12:00:00",
        ...             "completed_at": "2025-01-10T12:00:05",
        ...             "total_rows_in_file": 100,
        ...             "rows_saved": 85,
        ...             "rows_skipped": 5,
        ...             "rows_duplicate": 10,
        ...             "status": "completed",
        ...             "validation_status": "pass",
        ...             "file_name": "hana_statement.xls",
        ...             "institution_name": "하나카드"
        ...         }
        ...     ],
        ...     "total": 50,
        ...     "page": 1,
        ...     "page_size": 20
        ... }

    Notes:
        - Phase 2 will use ParsingSessionRepository.get_recent_sessions()
        - Sessions ordered by started_at DESC (most recent first)
        - Includes file name and institution name via joins
        - Useful for monitoring file processing history
    """
    # TODO Phase 2: Implement parsing session list
    # 1. Calculate offset from page and page_size
    # 2. Use ParsingSessionRepository.get_recent_sessions(limit, offset)
    # 3. Get total count for pagination metadata
    # 4. Convert to ParsingSessionListResponse

    raise HTTPException(
        status_code=status.HTTP_501_NOT_IMPLEMENTED,
        detail="Parsing session listing will be implemented in Phase 2"
    )


@router.get(
    "/{session_id}",
    response_model=ParsingSessionResponse,
    responses={
        401: {"model": ErrorResponse, "description": "Not authenticated"},
        404: {"model": ErrorResponse, "description": "Session not found"}
    }
)
async def get_parsing_session_by_id(
    session_id: int,
    db: sqlite3.Connection = Depends(get_db),
    current_user: UserInfo = Depends(get_current_user)
):
    """
    Get single parsing session by ID with full details.

    Returns complete parsing session information including file details,
    processing statistics, and validation results.

    **Implementation Status**: Skeleton - Phase 2 will implement actual query.

    Args:
        session_id: Parsing session database ID
        db: Database connection from dependency
        current_user: Current authenticated user

    Returns:
        ParsingSessionResponse with all session details

    Raises:
        HTTPException: 404 if session not found

    Examples:
        >>> # Get session with ID 123
        >>> GET /api/parsing-sessions/123

        >>> # Response
        >>> {
        ...     "id": 123,
        ...     "file_id": 45,
        ...     "parser_type": "TOSS",
        ...     "started_at": "2025-01-10T12:00:00",
        ...     "completed_at": "2025-01-10T12:00:03",
        ...     "total_rows_in_file": 50,
        ...     "rows_saved": 45,
        ...     "rows_skipped": 3,
        ...     "rows_duplicate": 2,
        ...     "status": "completed",
        ...     "validation_status": "pass",
        ...     "validation_notes": "All validations passed",
        ...     "file_name": "toss_statement.csv",
        ...     "file_hash": "abc123...",
        ...     "institution_name": "토스뱅크",
        ...     "institution_type": "BANK"
        ... }

    Notes:
        - Phase 2 will use ParsingSessionRepository.get_with_stats()
        - Returns 404 if session doesn't exist
        - Includes joined file and institution data
        - Useful for debugging parsing issues
    """
    # TODO Phase 2: Implement session detail query
    # 1. Use ParsingSessionRepository.get_with_stats(session_id)
    # 2. Return 404 if not found
    # 3. Convert to ParsingSessionResponse

    raise HTTPException(
        status_code=status.HTTP_501_NOT_IMPLEMENTED,
        detail="Parsing session detail will be implemented in Phase 2"
    )


@router.get(
    "/{session_id}/skipped",
    response_model=List[SkippedTransactionResponse],
    responses={
        401: {"model": ErrorResponse, "description": "Not authenticated"},
        404: {"model": ErrorResponse, "description": "Session not found"}
    }
)
async def get_skipped_transactions(
    session_id: int,
    db: sqlite3.Connection = Depends(get_db),
    current_user: UserInfo = Depends(get_current_user)
):
    """
    Get skipped transactions for a parsing session.

    Returns list of transactions that were skipped during parsing,
    with reasons and debugging information.

    **Implementation Status**: Skeleton - Phase 2 will implement actual query.

    Args:
        session_id: Parsing session database ID
        db: Database connection from dependency
        current_user: Current authenticated user

    Returns:
        List of SkippedTransactionResponse objects

    Raises:
        HTTPException: 404 if session not found

    Examples:
        >>> # Get skipped transactions for session 123
        >>> GET /api/parsing-sessions/123/skipped

        >>> # Response
        >>> [
        ...     {
        ...         "id": 1,
        ...         "session_id": 123,
        ...         "row_number": 5,
        ...         "skip_reason": "zero_amount",
        ...         "transaction_date": "2025.09.13",
        ...         "merchant_name": "Test Store",
        ...         "amount": 0,
        ...         "skip_details": "Amount is zero",
        ...         "column_data": {"col1": "value1"}
        ...     },
        ...     {
        ...         "id": 2,
        ...         "session_id": 123,
        ...         "row_number": 10,
        ...         "skip_reason": "invalid_date",
        ...         "skip_details": "Date format invalid"
        ...     }
        ... ]

    Notes:
        - Phase 2 will use SkippedTransactionRepository.get_by_session()
        - Ordered by row_number for sequential inspection
        - Useful for debugging parsing issues
        - Returns empty list if no skipped transactions
        - column_data contains raw column values for debugging
    """
    # TODO Phase 2: Implement skipped transactions query
    # 1. Verify session exists (or let FK constraint handle it)
    # 2. Use SkippedTransactionRepository.get_by_session(session_id)
    # 3. Convert to SkippedTransactionResponse models
    # 4. Return list (empty if none)

    raise HTTPException(
        status_code=status.HTTP_501_NOT_IMPLEMENTED,
        detail="Skipped transactions query will be implemented in Phase 2"
    )
