"""
Transaction routes for querying expense data.
Provides filtering, pagination, and aggregation endpoints.
"""

from fastapi import APIRouter, Depends, HTTPException, status, Query, Body
from typing import Optional
import sqlite3
import math
import logging

from backend.api.schemas import (
    TransactionResponse,
    TransactionListResponse,
    MonthlySummaryResponse,
    CategorySummary,
    ErrorResponse,
    TransactionCreateRequest,
    TransactionUpdateRequest,
    TransactionCategoryUpdateRequest,
    TransactionDeleteResponse
)
from backend.api.dependencies import get_current_user, get_db
from backend.api.schemas import UserInfo
from src.db.repository import TransactionRepository, CategoryRepository, InstitutionRepository
from src.models import Transaction

logger = logging.getLogger(__name__)

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
        notes=row.get('notes'),
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


@router.post(
    "",
    response_model=TransactionResponse,
    status_code=status.HTTP_201_CREATED,
    responses={
        400: {"model": ErrorResponse, "description": "Validation error or duplicate transaction"},
        401: {"model": ErrorResponse, "description": "Not authenticated"},
        500: {"model": ErrorResponse, "description": "Database error"}
    }
)
async def create_transaction(
    request: TransactionCreateRequest,
    db: sqlite3.Connection = Depends(get_db),
    current_user: UserInfo = Depends(get_current_user)
):
    """
    Create a new manual transaction.

    Creates a transaction that is marked as manually entered (file_id IS NULL).
    Manual transactions can be updated and deleted, unlike parsed transactions.

    Args:
        request: Transaction creation request with required fields
        db: Database connection from dependency
        current_user: Current authenticated user

    Returns:
        TransactionResponse with the created transaction details

    Raises:
        HTTPException: 400 if duplicate transaction detected or validation fails
        HTTPException: 401 if not authenticated
        HTTPException: 500 if database error occurs

    Examples:
        >>> # Create a food expense
        >>> POST /api/transactions
        >>> {
        ...     "date": "2025.09.15",
        ...     "category": "식비",
        ...     "merchant_name": "스타벅스 강남점",
        ...     "amount": 5500,
        ...     "institution": "신한카드",
        ...     "notes": "회의 중 커피"
        ... }

    Notes:
        - Manual transactions (file_id IS NULL) can be edited and deleted
        - Duplicate detection checks: date, institution, merchant, amount
        - Date format is yyyy.mm.dd (Korean format)
        - All amounts in KRW (Korean Won)
    """
    try:
        # Initialize repositories
        category_repo = CategoryRepository(db)
        institution_repo = InstitutionRepository(db)
        transaction_repo = TransactionRepository(db, category_repo, institution_repo)

        # Extract month from date (yyyy.mm.dd -> mm)
        date_parts = request.date.split('.')
        if len(date_parts) != 3:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="날짜 형식이 올바르지 않습니다. yyyy.mm.dd 형식이어야 합니다."
            )

        month = date_parts[1]

        # Create Transaction model from request
        # Note: Transaction model uses 'item' for merchant and 'source' for institution
        transaction = Transaction(
            month=month,
            date=request.date,
            category=request.category,
            item=request.merchant_name,
            amount=request.amount,
            source=request.institution,
            installment_months=request.installment_months,
            installment_current=request.installment_current,
            original_amount=request.original_amount
        )

        # Insert transaction with file_id=None, row_number=None (marks as manual)
        transaction_id = transaction_repo.insert(
            transaction,
            auto_commit=True,
            file_id=None,
            row_number=None
        )

        # Check for duplicate (INSERT OR IGNORE returns 0)
        if transaction_id == 0:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="동일한 거래가 이미 존재합니다. (날짜, 금융기관, 가맹점, 금액이 모두 같음)"
            )

        # If notes provided, update them separately
        if request.notes:
            transaction_repo.update(
                transaction_id,
                {'notes': request.notes},
                validate_editable=False  # Just created, safe to update
            )

        # Fetch created transaction
        created_transaction = transaction_repo.get_by_id(transaction_id)

        if created_transaction is None:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="거래가 생성되었지만 조회할 수 없습니다."
            )

        logger.info(f"Created manual transaction ID={transaction_id} by user={current_user.username}")

        return _db_row_to_transaction_response(created_transaction)

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to create transaction: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"거래 생성 중 오류가 발생했습니다: {str(e)}"
        )


@router.put(
    "/{transaction_id}",
    response_model=TransactionResponse,
    responses={
        400: {"model": ErrorResponse, "description": "Validation error"},
        401: {"model": ErrorResponse, "description": "Not authenticated"},
        403: {"model": ErrorResponse, "description": "Cannot edit parsed transaction"},
        404: {"model": ErrorResponse, "description": "Transaction not found"}
    }
)
async def update_transaction(
    transaction_id: int,
    request: TransactionUpdateRequest,
    db: sqlite3.Connection = Depends(get_db),
    current_user: UserInfo = Depends(get_current_user)
):
    """
    Update an existing manual transaction.

    Only manual transactions (file_id IS NULL) can be updated. Transactions
    parsed from files are immutable and will return 403 Forbidden.

    Args:
        transaction_id: Transaction database ID to update
        request: Transaction update request with optional fields
        db: Database connection from dependency
        current_user: Current authenticated user

    Returns:
        TransactionResponse with the updated transaction details

    Raises:
        HTTPException: 403 if transaction is from parsed file (not editable)
        HTTPException: 404 if transaction not found
        HTTPException: 400 if validation fails
        HTTPException: 401 if not authenticated

    Examples:
        >>> # Update merchant name and amount
        >>> PUT /api/transactions/123
        >>> {
        ...     "merchant_name": "스타벅스 역삼점",
        ...     "amount": 6000
        ... }

        >>> # Update category only
        >>> PUT /api/transactions/123
        >>> {
        ...     "category": "교통"
        ... }

    Notes:
        - Only provided fields will be updated (partial updates supported)
        - Parsed transactions (with file_id) cannot be edited
        - Category and institution are referenced by name, not ID
        - Date format must be yyyy.mm.dd if provided
    """
    try:
        # Initialize repositories
        category_repo = CategoryRepository(db)
        institution_repo = InstitutionRepository(db)
        transaction_repo = TransactionRepository(db, category_repo, institution_repo)

        # Check if transaction is editable
        if not transaction_repo.is_editable(transaction_id):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="파일에서 가져온 거래는 수정할 수 없습니다. 수동으로 입력한 거래만 수정 가능합니다."
            )

        # Build updates dict from request (exclude None values)
        updates = {}

        if request.date is not None:
            updates['transaction_date'] = request.date
            # Also update year and month
            date_parts = request.date.split('.')
            if len(date_parts) == 3:
                updates['transaction_year'] = int(date_parts[0])
                updates['transaction_month'] = int(date_parts[1])

        if request.category is not None:
            updates['category'] = request.category

        if request.merchant_name is not None:
            updates['merchant_name'] = request.merchant_name

        if request.amount is not None:
            updates['amount'] = request.amount

        if request.institution is not None:
            updates['institution'] = request.institution

        if request.installment_months is not None:
            updates['installment_months'] = request.installment_months

        if request.installment_current is not None:
            updates['installment_current'] = request.installment_current

        if request.original_amount is not None:
            updates['original_amount'] = request.original_amount

        # Validate we have something to update
        if not updates:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="업데이트할 필드가 없습니다."
            )

        # Call repository update (validate_editable=False since already checked)
        success = transaction_repo.update(transaction_id, updates, validate_editable=False)

        if not success:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"거래 내역을 찾을 수 없습니다. (ID: {transaction_id})"
            )

        # Fetch updated transaction
        updated_transaction = transaction_repo.get_by_id(transaction_id)

        if updated_transaction is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"거래 내역을 찾을 수 없습니다. (ID: {transaction_id})"
            )

        logger.info(f"Updated transaction ID={transaction_id} by user={current_user.username}")

        return _db_row_to_transaction_response(updated_transaction)

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to update transaction {transaction_id}: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"거래 수정 중 오류가 발생했습니다: {str(e)}"
        )


@router.delete(
    "/{transaction_id}",
    response_model=TransactionDeleteResponse,
    responses={
        401: {"model": ErrorResponse, "description": "Not authenticated"},
        403: {"model": ErrorResponse, "description": "Cannot delete parsed transaction"},
        404: {"model": ErrorResponse, "description": "Transaction not found"}
    }
)
async def delete_transaction(
    transaction_id: int,
    db: sqlite3.Connection = Depends(get_db),
    current_user: UserInfo = Depends(get_current_user)
):
    """
    Soft delete a manual transaction.

    Only manual transactions (file_id IS NULL) can be deleted. Transactions
    parsed from files are immutable and will return 403 Forbidden. Soft deletion
    sets the deleted_at timestamp, preserving data for audit trails.

    Args:
        transaction_id: Transaction database ID to delete
        db: Database connection from dependency
        current_user: Current authenticated user

    Returns:
        TransactionDeleteResponse with deletion confirmation and timestamp

    Raises:
        HTTPException: 403 if transaction is from parsed file (not editable)
        HTTPException: 404 if transaction not found
        HTTPException: 401 if not authenticated

    Examples:
        >>> # Delete transaction
        >>> DELETE /api/transactions/123

        >>> # Response
        >>> {
        ...     "id": 123,
        ...     "message": "Transaction deleted successfully",
        ...     "deleted_at": "2025-09-15T14:30:00Z"
        ... }

    Notes:
        - Soft deletion preserves transaction data (sets deleted_at timestamp)
        - Deleted transactions are excluded from queries by default
        - Only manual transactions can be deleted
        - Parsed transactions (with file_id) cannot be deleted
    """
    try:
        # Initialize repositories
        category_repo = CategoryRepository(db)
        institution_repo = InstitutionRepository(db)
        transaction_repo = TransactionRepository(db, category_repo, institution_repo)

        # Check if transaction is editable
        if not transaction_repo.is_editable(transaction_id):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="파일에서 가져온 거래는 삭제할 수 없습니다. 수동으로 입력한 거래만 삭제 가능합니다."
            )

        # Call repository soft_delete (validate_editable=False since already checked)
        success = transaction_repo.soft_delete(transaction_id, validate_editable=False)

        if not success:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"거래 내역을 찾을 수 없습니다. (ID: {transaction_id})"
            )

        # Fetch deleted_at timestamp from DB
        cursor = db.execute(
            "SELECT deleted_at FROM transactions WHERE id = ?",
            (transaction_id,)
        )
        row = cursor.fetchone()

        if row is None or row[0] is None:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="거래가 삭제되었지만 삭제 시각을 조회할 수 없습니다."
            )

        deleted_at = row[0]

        logger.info(f"Soft deleted transaction ID={transaction_id} by user={current_user.username}")

        return TransactionDeleteResponse(
            id=transaction_id,
            message="Transaction deleted successfully",
            deleted_at=deleted_at
        )

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to delete transaction {transaction_id}: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"거래 삭제 중 오류가 발생했습니다: {str(e)}"
        )


@router.patch(
    "/{transaction_id}/notes",
    response_model=TransactionResponse,
    responses={
        401: {"model": ErrorResponse, "description": "Not authenticated"},
        404: {"model": ErrorResponse, "description": "Transaction not found"}
    }
)
async def update_transaction_notes(
    transaction_id: int,
    notes: Optional[str] = Body(None, embed=True),
    db: sqlite3.Connection = Depends(get_db),
    current_user: UserInfo = Depends(get_current_user)
):
    """
    Update notes for any transaction (including parsed transactions).

    Unlike other transaction fields, notes can be updated for BOTH manual and
    file-based transactions. This allows users to add context to any transaction
    regardless of its source.

    Args:
        transaction_id: Transaction database ID to update
        notes: New notes text (max 500 characters) or None to clear notes
        db: Database connection from dependency
        current_user: Current authenticated user

    Returns:
        TransactionResponse with the updated transaction details

    Raises:
        HTTPException: 404 if transaction not found
        HTTPException: 401 if not authenticated

    Examples:
        >>> # Add notes to a transaction
        >>> PATCH /api/transactions/123/notes
        >>> {
        ...     "notes": "회의 중 커피 구매"
        ... }

        >>> # Clear notes
        >>> PATCH /api/transactions/123/notes
        >>> {
        ...     "notes": null
        ... }

    Notes:
        - Works for BOTH manual and parsed transactions
        - No file_id validation required
        - Notes can be up to 500 characters
        - Passing null clears the notes field
    """
    try:
        # Initialize repositories
        category_repo = CategoryRepository(db)
        institution_repo = InstitutionRepository(db)
        transaction_repo = TransactionRepository(db, category_repo, institution_repo)

        # Update notes using the repository method
        success = transaction_repo.update_notes(transaction_id, notes)

        if not success:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"거래 내역을 찾을 수 없습니다. (ID: {transaction_id})"
            )

        # Fetch updated transaction
        updated_transaction = transaction_repo.get_by_id(transaction_id)

        if updated_transaction is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"거래 내역을 찾을 수 없습니다. (ID: {transaction_id})"
            )

        logger.info(f"Updated notes for transaction ID={transaction_id} by user={current_user.username}")

        return _db_row_to_transaction_response(updated_transaction)

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to update notes for transaction {transaction_id}: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"메모 업데이트 중 오류가 발생했습니다: {str(e)}"
        )


@router.patch(
    "/{transaction_id}/category",
    response_model=TransactionResponse,
    responses={
        401: {"model": ErrorResponse, "description": "Not authenticated"},
        404: {"model": ErrorResponse, "description": "Transaction not found"}
    }
)
async def update_transaction_category(
    transaction_id: int,
    category: str = Body(..., embed=True),
    db: sqlite3.Connection = Depends(get_db),
    current_user: UserInfo = Depends(get_current_user)
):
    """
    Update category for any transaction (including parsed transactions).

    This is the ONLY field that can be updated for file-based transactions.
    Unlike other transaction fields, category updates are allowed for BOTH manual
    and file-based transactions to support user-driven categorization.

    Args:
        transaction_id: Transaction database ID to update
        category: Category name in Korean (e.g., 식비, 교통)
        db: Database connection from dependency
        current_user: Current authenticated user

    Returns:
        TransactionResponse with the updated transaction details

    Raises:
        HTTPException: 404 if transaction not found
        HTTPException: 401 if not authenticated

    Examples:
        >>> # Update category for any transaction
        >>> PATCH /api/transactions/123/category
        >>> {
        ...     "category": "식비"
        ... }

        >>> # Works for file-based transactions too
        >>> PATCH /api/transactions/456/category
        >>> {
        ...     "category": "교통"
        ... }

    Notes:
        - Works for BOTH manual and parsed transactions
        - No file_id validation required
        - Category is automatically created if it doesn't exist
        - This is the ONLY editable field for file-based transactions
    """
    try:
        # Initialize repositories
        category_repo = CategoryRepository(db)
        institution_repo = InstitutionRepository(db)
        transaction_repo = TransactionRepository(db, category_repo, institution_repo)

        # Get or create category ID from category name
        category_id = category_repo.get_or_create(category)

        # Update category using the repository method
        success = transaction_repo.update_category(transaction_id, category_id)

        if not success:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"거래 내역을 찾을 수 없습니다. (ID: {transaction_id})"
            )

        # Fetch updated transaction
        updated_transaction = transaction_repo.get_by_id(transaction_id)

        if updated_transaction is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"거래 내역을 찾을 수 없습니다. (ID: {transaction_id})"
            )

        logger.info(f"Updated category for transaction ID={transaction_id} to '{category}' by user={current_user.username}")

        return _db_row_to_transaction_response(updated_transaction)

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to update category for transaction {transaction_id}: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"카테고리 업데이트 중 오류가 발생했습니다: {str(e)}"
        )
