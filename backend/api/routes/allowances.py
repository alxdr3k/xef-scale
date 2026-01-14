"""
Allowance Management API

Personal allowance tracking allows users to mark transactions as private spending.
When marked as allowance:
- Transaction becomes visible only to the user who marked it
- Hidden from other workspace members
- Excluded from shared totals and statistics
- Appears only in personal allowance page
"""

from fastapi import APIRouter, Depends, HTTPException, Response, status
import sqlite3
from typing import Optional
import logging

from backend.api.dependencies import (
    get_current_user,
    get_db,
    get_workspace_membership,
    UserInfo
)
from backend.api.schemas import (
    AllowanceMarkRequest,
    AllowanceTransactionResponse,
    AllowanceListResponse,
    AllowanceSummaryResponse
)
from src.db.repository import (
    AllowanceTransactionRepository,
    TransactionRepository,
    WorkspaceRepository
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/workspaces", tags=["allowances"])


# ============================================================================
# POST /api/workspaces/{workspace_id}/allowances - Mark Transaction as Allowance
# ============================================================================


@router.post(
    "/{workspace_id}/allowances",
    response_model=AllowanceTransactionResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Mark transaction as personal allowance",
    description="""
    Mark a transaction as personal allowance (private spending).

    When marked as allowance:
    - Transaction becomes visible only to the current user
    - Hidden from other workspace members in transaction lists
    - Excluded from shared totals and workspace-wide statistics
    - Appears only in the user's personal allowance page

    **Privacy Model**: Allowance transactions are PRIVATE to the user who marked them.
    Each user can mark/unmark their own allowances independently.

    **Use Cases**:
    - Family workspace: Parent marks child's spending as "allowance"
    - Team workspace: Member marks personal expenses as "allowance"
    - Shared account: User marks their private spending
    """
)
async def mark_as_allowance(
    workspace_id: int,
    allowance_data: AllowanceMarkRequest,
    membership: dict = Depends(get_workspace_membership),
    current_user: UserInfo = Depends(get_current_user),
    db: sqlite3.Connection = Depends(get_db)
):
    """
    Mark transaction as personal allowance.

    Effect: Transaction becomes visible only to current user,
    hidden from other workspace members.

    Args:
        workspace_id: The workspace
        allowance_data: {transaction_id, notes (optional)}
        membership: Workspace membership details (injected)
        current_user: Current authenticated user (injected)
        db: Database connection (injected)

    Returns:
        Allowance record with transaction details

    Raises:
        404: Transaction not found
        400: Transaction not in workspace
        409: Already marked as allowance
    """
    logger.info(
        f"User {current_user.id} marking transaction {allowance_data.transaction_id} "
        f"as allowance in workspace {workspace_id}"
    )

    # Verify transaction exists and belongs to workspace
    transaction = TransactionRepository.get_by_id(db, allowance_data.transaction_id)
    if not transaction:
        logger.warning(f"Transaction {allowance_data.transaction_id} not found")
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Transaction not found"
        )

    if transaction['workspace_id'] != workspace_id:
        logger.warning(
            f"Transaction {allowance_data.transaction_id} belongs to workspace "
            f"{transaction['workspace_id']}, not {workspace_id}"
        )
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Transaction does not belong to this workspace"
        )

    # Check if already marked
    if AllowanceTransactionRepository.is_allowance(
        db, allowance_data.transaction_id, int(current_user.id), workspace_id
    ):
        logger.warning(
            f"Transaction {allowance_data.transaction_id} already marked as allowance "
            f"by user {current_user.id}"
        )
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Transaction is already marked as allowance"
        )

    # Mark as allowance
    allowance_id = AllowanceTransactionRepository.mark_as_allowance(
        db,
        transaction_id=allowance_data.transaction_id,
        user_id=int(current_user.id),
        workspace_id=workspace_id,
        notes=allowance_data.notes
    )

    logger.info(
        f"Created allowance {allowance_id} for transaction {allowance_data.transaction_id}"
    )

    # Get full transaction details for response
    allowances, _ = AllowanceTransactionRepository.get_user_allowances(
        db,
        user_id=int(current_user.id),
        workspace_id=workspace_id,
        filters={'transaction_id': allowance_data.transaction_id}
    )

    if not allowances:
        logger.error(
            f"Failed to retrieve marked allowance {allowance_id} after creation"
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve marked allowance"
        )

    return AllowanceTransactionResponse(**allowances[0])


# ============================================================================
# DELETE /api/workspaces/{workspace_id}/allowances/{transaction_id} - Unmark Allowance
# ============================================================================


@router.delete(
    "/{workspace_id}/allowances/{transaction_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Remove allowance marking from transaction",
    description="""
    Remove allowance marking from a transaction.

    Effect: Transaction becomes visible to all workspace members again and
    is included in shared totals and statistics.

    **Privacy**: Users can only unmark their own allowances. Cannot unmark
    allowances marked by other users.
    """
)
async def unmark_allowance(
    workspace_id: int,
    transaction_id: int,
    membership: dict = Depends(get_workspace_membership),
    current_user: UserInfo = Depends(get_current_user),
    db: sqlite3.Connection = Depends(get_db)
):
    """
    Remove allowance marking from transaction.

    Effect: Transaction becomes visible to all workspace members again.

    Args:
        workspace_id: The workspace
        transaction_id: Transaction to unmark
        membership: Workspace membership details (injected)
        current_user: Current authenticated user (injected)
        db: Database connection (injected)

    Raises:
        404: Not marked as allowance or doesn't exist
    """
    logger.info(
        f"User {current_user.id} unmarking transaction {transaction_id} "
        f"in workspace {workspace_id}"
    )

    success = AllowanceTransactionRepository.unmark_allowance(
        db,
        transaction_id=transaction_id,
        user_id=int(current_user.id),
        workspace_id=workspace_id
    )

    if not success:
        logger.warning(
            f"Transaction {transaction_id} is not marked as allowance "
            f"by user {current_user.id} in workspace {workspace_id}"
        )
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Transaction is not marked as allowance"
        )

    logger.info(f"Successfully unmarked transaction {transaction_id}")
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# ============================================================================
# GET /api/workspaces/{workspace_id}/allowances - List Personal Allowances
# ============================================================================


@router.get(
    "/{workspace_id}/allowances",
    response_model=AllowanceListResponse,
    summary="List personal allowance transactions",
    description="""
    Get current user's personal allowance transactions.

    **Private**: Only shows transactions marked as allowance by the current user.
    Other users' allowances are not visible.

    Supports filtering by:
    - Year and month
    - Category
    - Financial institution
    - Search term (merchant name)
    """
)
async def get_user_allowances(
    workspace_id: int,
    year: Optional[int] = None,
    month: Optional[int] = None,
    category_id: Optional[int] = None,
    institution_id: Optional[int] = None,
    search: Optional[str] = None,
    membership: dict = Depends(get_workspace_membership),
    current_user: UserInfo = Depends(get_current_user),
    db: sqlite3.Connection = Depends(get_db)
):
    """
    Get current user's personal allowance transactions.

    Private: Only shows transactions marked as allowance by current user.

    Args:
        workspace_id: The workspace
        year: Optional filter by year (e.g., 2025)
        month: Optional filter by month (1-12)
        category_id: Optional filter by category
        institution_id: Optional filter by financial institution
        search: Optional search term for merchant name
        membership: Workspace membership details (injected)
        current_user: Current authenticated user (injected)
        db: Database connection (injected)

    Returns:
        List of allowance transactions with totals
    """
    logger.info(
        f"User {current_user.id} fetching allowances in workspace {workspace_id} "
        f"(year={year}, month={month}, category={category_id}, "
        f"institution={institution_id}, search={search})"
    )

    # Build filters dictionary
    filters = {}
    if year is not None:
        filters['year'] = year
    if month is not None:
        filters['month'] = month
    if category_id is not None:
        filters['category_id'] = category_id
    if institution_id is not None:
        filters['institution_id'] = institution_id
    if search is not None:
        filters['search'] = search

    # Get allowances
    allowances, total = AllowanceTransactionRepository.get_user_allowances(
        db,
        user_id=int(current_user.id),
        workspace_id=workspace_id,
        filters=filters if filters else None
    )

    # Calculate total amount
    total_amount = sum(a['amount'] for a in allowances)

    # Get workspace name
    workspace = WorkspaceRepository.get_by_id(db, workspace_id)

    logger.info(
        f"Found {total} allowance transactions "
        f"(total amount: {total_amount})"
    )

    return AllowanceListResponse(
        data=[AllowanceTransactionResponse(**a) for a in allowances],
        total=total,
        total_amount=total_amount,
        workspace={
            "id": workspace_id,
            "name": workspace['name']
        }
    )


# ============================================================================
# GET /api/workspaces/{workspace_id}/allowances/summary - Get Allowance Summary
# ============================================================================


@router.get(
    "/{workspace_id}/allowances/summary",
    response_model=AllowanceSummaryResponse,
    summary="Get monthly allowance spending summary",
    description="""
    Get monthly allowance spending statistics with category breakdown.

    **Private**: Only shows current user's personal allowances.
    Provides aggregated spending data for a specific month.

    Returns:
    - Total allowance spending for the month
    - Transaction count
    - Category-wise breakdown (amount and count per category)
    """
)
async def get_allowance_summary(
    workspace_id: int,
    year: int,
    month: int,
    membership: dict = Depends(get_workspace_membership),
    current_user: UserInfo = Depends(get_current_user),
    db: sqlite3.Connection = Depends(get_db)
):
    """
    Get monthly allowance spending summary.

    Private: Only shows current user's personal allowances.

    Args:
        workspace_id: The workspace
        year: Year (e.g., 2025)
        month: Month (1-12)
        membership: Workspace membership details (injected)
        current_user: Current authenticated user (injected)
        db: Database connection (injected)

    Returns:
        Monthly statistics with category breakdown
    """
    logger.info(
        f"User {current_user.id} fetching allowance summary "
        f"for {year}-{month:02d} in workspace {workspace_id}"
    )

    summary = AllowanceTransactionRepository.get_allowance_summary(
        db,
        user_id=int(current_user.id),
        workspace_id=workspace_id,
        year=year,
        month=month
    )

    logger.info(
        f"Summary: {summary['transaction_count']} transactions, "
        f"total amount: {summary['total_amount']}, "
        f"{len(summary['by_category'])} categories"
    )

    return AllowanceSummaryResponse(**summary)
