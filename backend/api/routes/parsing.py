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
        - Uses ParsingSessionRepository.get_recent_sessions()
        - Sessions ordered by started_at DESC (most recent first)
        - Includes file name and institution name via joins
        - Useful for monitoring file processing history
    """
    try:
        parsing_repo = ParsingSessionRepository(db)

        # Calculate offset from page (1-indexed)
        offset = (page - 1) * page_size

        # Get sessions with pagination
        sessions = parsing_repo.get_recent_sessions(limit=page_size, offset=offset)

        # Get total count for pagination
        cursor = db.execute('SELECT COUNT(*) FROM parsing_sessions')
        total = cursor.fetchone()[0]

        # Convert to response models
        session_responses = [
            ParsingSessionResponse(
                id=session['id'],
                file_id=session['file_id'],
                parser_type=session['parser_type'],
                started_at=session['started_at'],
                completed_at=session.get('completed_at'),
                total_rows_in_file=session['total_rows_in_file'],
                rows_saved=session.get('rows_saved', 0),
                rows_skipped=session.get('rows_skipped', 0),
                rows_duplicate=session.get('rows_duplicate', 0),
                status=session['status'],
                error_message=session.get('error_message'),
                validation_status=session.get('validation_status'),
                validation_notes=session.get('validation_notes'),
                file_name=session.get('file_name'),
                file_hash=session.get('file_hash'),
                institution_name=session.get('institution_name'),
                institution_type=session.get('institution_type')
            )
            for session in sessions
        ]

        return ParsingSessionListResponse(
            sessions=session_responses,
            total=total,
            page=page,
            page_size=page_size
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to retrieve parsing sessions: {str(e)}"
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
        - Uses ParsingSessionRepository.get_with_stats()
        - Returns 404 if session doesn't exist
        - Includes joined file and institution data
        - Useful for debugging parsing issues
    """
    try:
        parsing_repo = ParsingSessionRepository(db)
        session = parsing_repo.get_with_stats(session_id)

        if session is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Parsing session {session_id} not found"
            )

        return ParsingSessionResponse(
            id=session['id'],
            file_id=session['file_id'],
            parser_type=session['parser_type'],
            started_at=session['started_at'],
            completed_at=session.get('completed_at'),
            total_rows_in_file=session['total_rows_in_file'],
            rows_saved=session.get('rows_saved', 0),
            rows_skipped=session.get('rows_skipped', 0),
            rows_duplicate=session.get('rows_duplicate', 0),
            status=session['status'],
            error_message=session.get('error_message'),
            validation_status=session.get('validation_status'),
            validation_notes=session.get('validation_notes'),
            file_name=session.get('file_name'),
            file_hash=session.get('file_hash'),
            institution_name=session.get('institution_name'),
            institution_type=session.get('institution_type')
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to retrieve parsing session: {str(e)}"
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
        - Uses SkippedTransactionRepository.get_by_session()
        - Ordered by row_number for sequential inspection
        - Useful for debugging parsing issues
        - Returns empty list if no skipped transactions
        - column_data contains raw column values for debugging
    """
    try:
        # Verify session exists first
        parsing_repo = ParsingSessionRepository(db)
        session = parsing_repo.get_with_stats(session_id)

        if session is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Parsing session {session_id} not found"
            )

        # Get skipped transactions
        skipped_repo = SkippedTransactionRepository(db)
        skipped_transactions = skipped_repo.get_by_session(session_id)

        # Convert to response models
        import json
        return [
            SkippedTransactionResponse(
                id=skipped['id'],
                session_id=skipped['session_id'],
                row_number=skipped['row_number'],
                skip_reason=skipped['skip_reason'],
                transaction_date=skipped.get('transaction_date'),
                merchant_name=skipped.get('merchant_name'),
                amount=skipped.get('amount'),
                original_amount=skipped.get('original_amount'),
                skip_details=skipped.get('skip_details'),
                column_data=json.loads(skipped['column_data']) if skipped.get('column_data') else None
            )
            for skipped in skipped_transactions
        ]
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to retrieve skipped transactions: {str(e)}"
        )
