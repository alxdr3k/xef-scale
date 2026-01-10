"""
Transaction routes for querying expense data.
Provides filtering, pagination, and aggregation endpoints.
"""

from fastapi import APIRouter, Depends, HTTPException, status, Query
from typing import Optional
import sqlite3

from backend.api.schemas import (
    TransactionResponse,
    TransactionListResponse,
    MonthlySummaryResponse,
    TransactionSummary,
    ErrorResponse
)
from backend.api.dependencies import get_current_user, get_db
from backend.api.schemas import UserInfo
from src.db.repository import TransactionRepository, CategoryRepository, InstitutionRepository

router = APIRouter(prefix="/transactions", tags=["Transactions"])


@router.get(
    "",
    response_model=TransactionListResponse,
    responses={
        401: {"model": ErrorResponse, "description": "Not authenticated"}
    }
)
async def get_transactions(
    year: Optional[int] = Query(None, description="Filter by year"),
    month: Optional[int] = Query(None, ge=1, le=12, description="Filter by month (1-12)"),
    category: Optional[str] = Query(None, description="Filter by category name"),
    institution: Optional[str] = Query(None, description="Filter by institution name"),
    page: int = Query(1, ge=1, description="Page number (1-indexed)"),
    page_size: int = Query(50, ge=1, le=200, description="Items per page"),
    db: sqlite3.Connection = Depends(get_db),
    current_user: UserInfo = Depends(get_current_user)
):
    """
    Get paginated list of transactions with optional filters.

    Returns transactions sorted by date (most recent first) with pagination
    and optional filtering by year, month, category, and institution.

    **Implementation Status**: Skeleton - Phase 2 will implement actual queries.

    Args:
        year: Optional year filter (e.g., 2025)
        month: Optional month filter (1-12)
        category: Optional category name filter (Korean)
        institution: Optional institution name filter (Korean)
        page: Page number for pagination (1-indexed)
        page_size: Number of items per page (max 200)
        db: Database connection from dependency
        current_user: Current authenticated user

    Returns:
        TransactionListResponse with transactions array, total count, and pagination info

    Examples:
        >>> # Get all transactions for September 2025
        >>> GET /api/transactions?year=2025&month=9

        >>> # Get food expenses from Hana Card
        >>> GET /api/transactions?category=식비&institution=하나카드

        >>> # Paginate through results
        >>> GET /api/transactions?page=2&page_size=100

    Notes:
        - Default page_size is 50, max is 200
        - Transactions ordered by date DESC (most recent first)
        - Phase 2 will implement actual database queries
        - Will use TransactionRepository for data access
    """
    # TODO Phase 2: Implement transaction queries
    # 1. Build dynamic SQL query based on filters
    # 2. Apply pagination (LIMIT/OFFSET)
    # 3. Get total count for pagination metadata
    # 4. Convert database rows to TransactionResponse models
    # 5. Handle category/institution name lookups

    raise HTTPException(
        status_code=status.HTTP_501_NOT_IMPLEMENTED,
        detail="Transaction queries will be implemented in Phase 2"
    )


@router.get(
    "/{transaction_id}",
    response_model=TransactionResponse,
    responses={
        401: {"model": ErrorResponse, "description": "Not authenticated"},
        404: {"model": ErrorResponse, "description": "Transaction not found"}
    }
)
async def get_transaction_by_id(
    transaction_id: int,
    db: sqlite3.Connection = Depends(get_db),
    current_user: UserInfo = Depends(get_current_user)
):
    """
    Get single transaction by ID.

    Returns detailed information for a specific transaction.

    **Implementation Status**: Skeleton - Phase 2 will implement actual query.

    Args:
        transaction_id: Transaction database ID
        db: Database connection from dependency
        current_user: Current authenticated user

    Returns:
        TransactionResponse with all transaction details

    Raises:
        HTTPException: 404 if transaction not found

    Examples:
        >>> # Get transaction with ID 123
        >>> GET /api/transactions/123

    Notes:
        - Phase 2 will implement database query
        - Will join with categories and institutions for names
        - Returns 404 if transaction doesn't exist
    """
    # TODO Phase 2: Implement single transaction query
    # 1. Query transactions table by ID
    # 2. Join with categories and financial_institutions
    # 3. Convert to TransactionResponse
    # 4. Return 404 if not found

    raise HTTPException(
        status_code=status.HTTP_501_NOT_IMPLEMENTED,
        detail="Transaction detail query will be implemented in Phase 2"
    )


@router.get(
    "/summary/monthly",
    response_model=MonthlySummaryResponse,
    responses={
        401: {"model": ErrorResponse, "description": "Not authenticated"}
    }
)
async def get_monthly_summary(
    year: int = Query(..., description="Year for summary"),
    month: int = Query(..., ge=1, le=12, description="Month for summary (1-12)"),
    db: sqlite3.Connection = Depends(get_db),
    current_user: UserInfo = Depends(get_current_user)
):
    """
    Get monthly spending summary aggregated by category.

    Returns total spending for each category in the specified month,
    sorted by total spending (highest first).

    **Implementation Status**: Skeleton - Phase 2 will implement actual aggregation.

    Args:
        year: Year for summary (required)
        month: Month for summary, 1-12 (required)
        db: Database connection from dependency
        current_user: Current authenticated user

    Returns:
        MonthlySummaryResponse with category summaries and total spending

    Examples:
        >>> # Get September 2025 summary
        >>> GET /api/transactions/summary/monthly?year=2025&month=9

        >>> # Response
        >>> {
        ...     "year": 2025,
        ...     "month": 9,
        ...     "categories": [
        ...         {"category": "식비", "total": 450000},
        ...         {"category": "교통", "total": 120000},
        ...         {"category": "통신", "total": 80000}
        ...     ],
        ...     "total_spending": 650000
        ... }

    Notes:
        - Phase 2 will use TransactionRepository.get_monthly_summary()
        - Categories sorted by spending amount (highest first)
        - Useful for monthly expense analysis and budgeting
        - Can be used to generate charts/graphs
    """
    # TODO Phase 2: Implement monthly summary
    # 1. Use TransactionRepository.get_monthly_summary(year, month)
    # 2. Calculate total_spending sum
    # 3. Convert to MonthlySummaryResponse

    raise HTTPException(
        status_code=status.HTTP_501_NOT_IMPLEMENTED,
        detail="Monthly summary will be implemented in Phase 2"
    )
