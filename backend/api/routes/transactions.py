"""
Transaction routes for querying expense data.
Provides filtering, pagination, and aggregation endpoints.
"""

from fastapi import APIRouter, Depends, HTTPException, status, Query
from typing import Optional
import sqlite3
import math

from backend.api.schemas import (
    TransactionResponse,
    TransactionListResponse,
    MonthlySummaryResponse,
    CategorySummary,
    ErrorResponse
)
from backend.api.dependencies import get_current_user, get_db
from backend.api.schemas import UserInfo
from src.db.repository import TransactionRepository, CategoryRepository, InstitutionRepository

router = APIRouter(prefix="/transactions", tags=["Transactions"])


def _db_row_to_transaction_response(row: dict) -> TransactionResponse:
    """
    Convert database row dict to TransactionResponse schema.

    Maps database column names to API response field names.

    Args:
        row: Database row as dict (with Row factory)

    Returns:
        TransactionResponse with all fields populated

    Notes:
        - Converts transaction_date from 'yyyy-mm-dd' to 'yyyy.mm.dd'
        - Maps category_name to 'category' field
        - Maps institution_name to 'institution' field
        - Handles nullable installment fields
    """
    # Convert date format from SQL (yyyy-mm-dd) to API (yyyy.mm.dd)
    date_parts = row['transaction_date'].split('-')
    formatted_date = f"{date_parts[0]}.{date_parts[1]}.{date_parts[2]}"

    return TransactionResponse(
        id=row['id'],
        date=formatted_date,
        category=row['category_name'],
        merchant_name=row['merchant_name'],
        amount=row['amount'],
        institution=row['institution_name'],
        installment_months=row.get('installment_months'),
        installment_current=row.get('installment_current'),
        original_amount=row.get('original_amount'),
        transaction_year=row['transaction_year'],
        transaction_month=row['transaction_month'],
        category_id=row['category_id'],
        institution_id=row['institution_id'],
        file_id=row.get('file_id'),
        row_number_in_file=row.get('row_number_in_file'),
        created_at=row['created_at']
    )


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
    category_id: Optional[int] = Query(None, description="Filter by category ID"),
    institution_id: Optional[int] = Query(None, description="Filter by institution ID"),
    search: Optional[str] = Query(None, description="Search merchant name (partial match)"),
    sort: str = Query("date_desc", description="Sort order: date_desc, date_asc, amount_desc, amount_asc"),
    page: int = Query(1, ge=1, description="Page number (1-indexed)"),
    limit: int = Query(50, ge=1, le=200, description="Items per page"),
    db: sqlite3.Connection = Depends(get_db),
    current_user: UserInfo = Depends(get_current_user)
):
    """
    Get paginated list of transactions with optional filters.

    Returns transactions sorted by date (most recent first) with pagination
    and optional filtering by year, month, category, institution, and merchant search.

    Args:
        year: Optional year filter (e.g., 2025)
        month: Optional month filter (1-12)
        category_id: Optional category ID filter
        institution_id: Optional institution ID filter
        search: Optional merchant name search (partial, case-insensitive)
        sort: Sort order (date_desc, date_asc, amount_desc, amount_asc)
        page: Page number for pagination (1-indexed)
        limit: Number of items per page (max 200)
        db: Database connection from dependency
        current_user: Current authenticated user

    Returns:
        TransactionListResponse with data array, total count, and pagination info

    Examples:
        >>> # Get all transactions for September 2025
        >>> GET /api/transactions?year=2025&month=9

        >>> # Get food expenses (category_id=1) from Hana Card (institution_id=1)
        >>> GET /api/transactions?category_id=1&institution_id=1

        >>> # Search for Starbucks transactions
        >>> GET /api/transactions?search=스타벅스

        >>> # Paginate through results
        >>> GET /api/transactions?page=2&limit=100

    Notes:
        - Default limit is 50, max is 200
        - Default sort is date_desc (most recent first)
        - All filters can be combined
        - Search is case-insensitive and matches partial merchant names
    """
    # Initialize repositories
    category_repo = CategoryRepository(db)
    institution_repo = InstitutionRepository(db)
    transaction_repo = TransactionRepository(db, category_repo, institution_repo)

    # Validate sort parameter
    valid_sorts = {'date_desc', 'date_asc', 'amount_desc', 'amount_asc'}
    if sort not in valid_sorts:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid sort parameter. Must be one of: {', '.join(valid_sorts)}"
        )

    # Calculate offset from page number
    offset = (page - 1) * limit

    # Query transactions with filters
    transactions, total = transaction_repo.get_filtered(
        year=year,
        month=month,
        category_id=category_id,
        institution_id=institution_id,
        search=search,
        sort=sort,
        limit=limit,
        offset=offset
    )

    # Convert database rows to API response models
    transaction_responses = [_db_row_to_transaction_response(row) for row in transactions]

    # Calculate total pages
    total_pages = math.ceil(total / limit) if total > 0 else 0

    return TransactionListResponse(
        data=transaction_responses,
        total=total,
        page=page,
        limit=limit,
        total_pages=total_pages
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

    Returns detailed information for a specific transaction including
    category and institution names.

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
        - Joins with categories and institutions for readable names
        - Returns 404 if transaction doesn't exist
    """
    # Initialize repositories
    category_repo = CategoryRepository(db)
    institution_repo = InstitutionRepository(db)
    transaction_repo = TransactionRepository(db, category_repo, institution_repo)

    # Query transaction by ID
    transaction = transaction_repo.get_by_id(transaction_id)

    if transaction is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Transaction with ID {transaction_id} not found"
        )

    # Convert to API response
    return _db_row_to_transaction_response(transaction)


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
    sorted by total spending (highest first), along with transaction counts
    and overall totals.

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
        ...     "total_amount": 1234500,
        ...     "transaction_count": 56,
        ...     "by_category": [
        ...         {"category_id": 1, "category_name": "식비", "amount": 450000, "count": 20},
        ...         {"category_id": 2, "category_name": "교통", "amount": 120000, "count": 15},
        ...         {"category_id": 3, "category_name": "통신", "amount": 80000, "count": 3}
        ...     ]
        ... }

    Notes:
        - Categories sorted by spending amount (highest first)
        - Includes both amount and transaction count per category
        - Useful for monthly expense analysis and budgeting
        - Can be used to generate charts/graphs
    """
    # Initialize repositories
    category_repo = CategoryRepository(db)
    institution_repo = InstitutionRepository(db)
    transaction_repo = TransactionRepository(db, category_repo, institution_repo)

    # Get comprehensive monthly summary
    summary = transaction_repo.get_monthly_summary_with_stats(year, month)

    # Convert category summaries to API response models
    category_summaries = [
        CategorySummary(
            category_id=cat['category_id'],
            category_name=cat['category_name'],
            amount=cat['amount'],
            count=cat['count']
        )
        for cat in summary['by_category']
    ]

    return MonthlySummaryResponse(
        year=summary['year'],
        month=summary['month'],
        total_amount=summary['total_amount'],
        transaction_count=summary['transaction_count'],
        by_category=category_summaries
    )
