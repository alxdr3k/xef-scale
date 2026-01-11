"""
Duplicate confirmation routes for managing user decisions on potential duplicates.
Provides endpoints for listing, reviewing, and resolving duplicate transaction confirmations.
"""

from fastapi import APIRouter, Depends, HTTPException, status, Query
from typing import List, Optional
import sqlite3
import json

from backend.api.schemas import (
    DuplicateConfirmationResponse,
    ConfirmationActionRequest,
    BulkConfirmationResponse,
    ErrorResponse,
    UserInfo
)
from backend.api.dependencies import get_current_user, get_db
from src.db.repository import (
    DuplicateConfirmationRepository,
    ParsingSessionRepository
)

router = APIRouter(prefix="/confirmations", tags=["Confirmations"])


def _db_row_to_confirmation_response(row: dict) -> DuplicateConfirmationResponse:
    """
    Convert database row dict to DuplicateConfirmationResponse schema.

    Parses JSON fields and constructs full transaction objects for API response.

    Args:
        row: Database row as dict (with Row factory)

    Returns:
        DuplicateConfirmationResponse with parsed transaction data

    Notes:
        - Parses new_transaction_data from JSON string to dict
        - Parses match_fields from JSON array string to list
        - Constructs existing_transaction dict from joined columns
        - Handles nullable fields appropriately
    """
    # Parse JSON fields
    new_transaction = json.loads(row['new_transaction_data'])
    match_fields = json.loads(row['match_fields'])

    # Construct existing transaction object from joined columns
    existing_transaction = {
        'id': row['existing_transaction_id'],
        'date': row['existing_transaction_date'],
        'merchant_name': row['existing_merchant_name'],
        'amount': row['existing_amount'],
        'category_id': row['existing_category_id'],
        'category_name': row['existing_category_name'],
        'institution_id': row['existing_institution_id'],
        'institution_name': row['existing_institution_name'],
        'installment_months': row.get('existing_installment_months'),
        'installment_current': row.get('existing_installment_current'),
        'original_amount': row.get('existing_original_amount')
    }

    return DuplicateConfirmationResponse(
        id=row['id'],
        session_id=row['session_id'],
        new_transaction=new_transaction,
        new_transaction_index=row['new_transaction_index'],
        existing_transaction=existing_transaction,
        confidence_score=row['confidence_score'],
        match_fields=match_fields,
        difference_summary=row.get('difference_summary'),
        status=row['status'],
        created_at=row['created_at'],
        expires_at=row['expires_at']
    )


@router.get(
    "",
    response_model=List[DuplicateConfirmationResponse],
    responses={
        401: {"model": ErrorResponse, "description": "Not authenticated"}
    }
)
async def get_all_confirmations(
    status_filter: Optional[str] = Query('pending', description="Filter by status (default: pending)"),
    db: sqlite3.Connection = Depends(get_db),
    current_user: UserInfo = Depends(get_current_user)
):
    """
    Get all duplicate confirmations across all sessions.

    Returns list of confirmations filtered by status. Default is pending confirmations.
    Useful for global review queue showing all pending duplicates.

    Args:
        status_filter: Optional status filter (default: 'pending')
        db: Database connection from dependency
        current_user: Current authenticated user

    Returns:
        List of DuplicateConfirmationResponse with full transaction details

    Examples:
        >>> # Get all pending confirmations
        >>> GET /api/confirmations

        >>> # Get all confirmed (inserted) confirmations
        >>> GET /api/confirmations?status_filter=confirmed_insert

    Notes:
        - Default status filter is 'pending'
        - Ordered by created_at DESC (most recent first)
        - Includes full transaction details for both new and existing transactions
        - Requires authentication
    """
    # Initialize repository
    conf_repo = DuplicateConfirmationRepository(db)

    # Get confirmations based on status filter
    if status_filter == 'pending':
        confirmations = conf_repo.get_all_pending()
    else:
        # For other statuses, we need to query directly
        cursor = db.execute('''
            SELECT
                dc.*,
                t.transaction_date as existing_transaction_date,
                t.merchant_name as existing_merchant_name,
                t.amount as existing_amount,
                t.category_id as existing_category_id,
                t.institution_id as existing_institution_id,
                t.installment_months as existing_installment_months,
                t.installment_current as existing_installment_current,
                t.original_amount as existing_original_amount,
                c.name as existing_category_name,
                fi.name as existing_institution_name
            FROM duplicate_transaction_confirmations dc
            JOIN transactions t ON dc.existing_transaction_id = t.id
            JOIN categories c ON t.category_id = c.id
            JOIN financial_institutions fi ON t.institution_id = fi.id
            WHERE dc.status = ?
            ORDER BY dc.created_at DESC
        ''', (status_filter,))
        confirmations = [dict(row) for row in cursor.fetchall()]

    # Convert to response models
    confirmation_responses = [_db_row_to_confirmation_response(row) for row in confirmations]

    return confirmation_responses


@router.get(
    "/session/{session_id}",
    response_model=List[DuplicateConfirmationResponse],
    responses={
        401: {"model": ErrorResponse, "description": "Not authenticated"},
        404: {"model": ErrorResponse, "description": "Session not found"}
    }
)
async def get_confirmations_by_session(
    session_id: int,
    db: sqlite3.Connection = Depends(get_db),
    current_user: UserInfo = Depends(get_current_user)
):
    """
    Get all duplicate confirmations for a specific parsing session.

    Returns all confirmations (pending and resolved) for a session, ordered
    by transaction index for sequential review.

    Args:
        session_id: Parsing session ID
        db: Database connection from dependency
        current_user: Current authenticated user

    Returns:
        List of DuplicateConfirmationResponse for the session

    Raises:
        HTTPException: 404 if session not found

    Examples:
        >>> # Get all confirmations for session 123
        >>> GET /api/confirmations/session/123

    Notes:
        - Ordered by new_transaction_index ASC (sequential order)
        - Includes full transaction details for both new and existing transactions
        - Returns empty list if no confirmations found for session
        - Session must exist in parsing_sessions table
    """
    # Initialize repositories
    conf_repo = DuplicateConfirmationRepository(db)
    session_repo = ParsingSessionRepository(db)

    # Verify session exists
    cursor = db.execute('SELECT id FROM parsing_sessions WHERE id = ?', (session_id,))
    if not cursor.fetchone():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Parsing session with ID {session_id} not found"
        )

    # Get confirmations for session
    confirmations = conf_repo.get_by_session(session_id)

    # Convert to response models
    confirmation_responses = [_db_row_to_confirmation_response(row) for row in confirmations]

    return confirmation_responses


@router.post(
    "/{confirmation_id}/confirm",
    response_model=DuplicateConfirmationResponse,
    responses={
        401: {"model": ErrorResponse, "description": "Not authenticated"},
        404: {"model": ErrorResponse, "description": "Confirmation not found"},
        400: {"model": ErrorResponse, "description": "Invalid action"}
    }
)
async def apply_confirmation_decision(
    confirmation_id: int,
    action_request: ConfirmationActionRequest,
    db: sqlite3.Connection = Depends(get_db),
    current_user: UserInfo = Depends(get_current_user)
):
    """
    Apply user decision to a single duplicate confirmation.

    Processes user's decision for a potential duplicate transaction:
    - 'insert': Insert the new transaction into database
    - 'skip': Skip the transaction (it's a duplicate)
    - 'merge': Mark for merge (future feature)

    After processing all confirmations in a session, automatically updates
    session status to 'completed'.

    Args:
        confirmation_id: Confirmation ID to process
        action_request: Request body with action (insert/skip/merge)
        db: Database connection from dependency
        current_user: Current authenticated user

    Returns:
        Updated DuplicateConfirmationResponse

    Raises:
        HTTPException: 404 if confirmation not found
        HTTPException: 400 if action is invalid

    Examples:
        >>> # Insert the new transaction
        >>> POST /api/confirmations/123/confirm
        >>> {"action": "insert"}

        >>> # Skip (it's a duplicate)
        >>> POST /api/confirmations/124/confirm
        >>> {"action": "skip"}

    Notes:
        - User ID extracted from JWT token
        - Action validated by Pydantic schema
        - Transaction committed atomically with confirmation update
        - If all confirmations in session are resolved, session status updated to 'completed'
    """
    # Initialize repositories
    conf_repo = DuplicateConfirmationRepository(db)
    session_repo = ParsingSessionRepository(db)

    # Verify confirmation exists
    confirmation = conf_repo.get_by_id(confirmation_id)
    if not confirmation:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Confirmation with ID {confirmation_id} not found"
        )

    # Apply user decision
    try:
        updated = conf_repo.apply_user_decision(
            confirmation_id=confirmation_id,
            action=action_request.action,
            user_id=current_user.id
        )
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to apply decision: {str(e)}"
        )

    # Check if all confirmations in session are resolved
    session_id = updated['session_id']
    pending_count = conf_repo.get_pending_count_by_session(session_id)

    if pending_count == 0:
        # All confirmations resolved - update session status to completed
        session_repo.update_status(session_id, 'completed')

    # Fetch full confirmation details with joined transaction data
    confirmations = conf_repo.get_by_session(session_id)
    updated_confirmation = next((c for c in confirmations if c['id'] == confirmation_id), None)

    if not updated_confirmation:
        # Fallback: return minimal data if join query fails
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Confirmation updated but failed to retrieve full details"
        )

    return _db_row_to_confirmation_response(updated_confirmation)


@router.post(
    "/session/{session_id}/bulk-confirm",
    response_model=BulkConfirmationResponse,
    responses={
        401: {"model": ErrorResponse, "description": "Not authenticated"},
        404: {"model": ErrorResponse, "description": "Session not found"},
        400: {"model": ErrorResponse, "description": "Invalid action"}
    }
)
async def bulk_confirm_session(
    session_id: int,
    action_request: ConfirmationActionRequest,
    db: sqlite3.Connection = Depends(get_db),
    current_user: UserInfo = Depends(get_current_user)
):
    """
    Apply same action to all pending confirmations in a session.

    Bulk operation for convenience. Useful for workflows like:
    - "Skip all duplicates in this session"
    - "Insert all transactions from this session"

    After processing, automatically updates session status to 'completed'.

    Args:
        session_id: Parsing session ID
        action_request: Request body with action (insert/skip/merge)
        db: Database connection from dependency
        current_user: Current authenticated user

    Returns:
        BulkConfirmationResponse with processed count and session ID

    Raises:
        HTTPException: 404 if session not found
        HTTPException: 400 if action is invalid

    Examples:
        >>> # Skip all pending duplicates in session
        >>> POST /api/confirmations/session/123/bulk-confirm
        >>> {"action": "skip"}

        >>> # Insert all pending transactions
        >>> POST /api/confirmations/session/123/bulk-confirm
        >>> {"action": "insert"}

    Notes:
        - Only processes pending confirmations
        - User ID extracted from JWT token
        - All operations in single transaction (atomic)
        - Session status updated to 'completed' after processing
        - Use with caution for 'insert' action (creates many transactions)
    """
    # Initialize repositories
    conf_repo = DuplicateConfirmationRepository(db)
    session_repo = ParsingSessionRepository(db)

    # Verify session exists
    cursor = db.execute('SELECT id FROM parsing_sessions WHERE id = ?', (session_id,))
    if not cursor.fetchone():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Parsing session with ID {session_id} not found"
        )

    # Apply bulk decision
    try:
        processed_count = conf_repo.bulk_confirm_session(
            session_id=session_id,
            action=action_request.action,
            user_id=current_user.id
        )
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to apply bulk decision: {str(e)}"
        )

    # Update session status to completed (all confirmations resolved)
    if processed_count > 0:
        session_repo.update_status(session_id, 'completed')

    return BulkConfirmationResponse(
        processed_count=processed_count,
        session_id=session_id
    )
