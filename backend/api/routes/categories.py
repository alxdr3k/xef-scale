"""
Category routes for managing expense categories.
Provides read-only access to categories.
"""

from fastapi import APIRouter, Depends, HTTPException, status
from typing import List
import sqlite3

from backend.api.schemas import CategoryResponse, ErrorResponse, UserInfo
from backend.api.dependencies import get_current_user, get_db
from src.db.repository import CategoryRepository

router = APIRouter(prefix="/categories", tags=["Categories"])


@router.get(
    "",
    response_model=List[CategoryResponse],
    responses={
        401: {"model": ErrorResponse, "description": "Not authenticated"}
    }
)
async def get_categories(
    db: sqlite3.Connection = Depends(get_db),
    current_user: UserInfo = Depends(get_current_user)
):
    """
    Get all expense categories.

    Returns list of all categories sorted alphabetically by name.
    Categories are automatically created during transaction parsing.

    Args:
        db: Database connection from dependency
        current_user: Current authenticated user

    Returns:
        List of CategoryResponse objects with id, name, and timestamps

    Examples:
        >>> # Get all categories
        >>> GET /api/categories

        >>> # Response
        >>> [
        ...     {"id": 1, "name": "식비", "created_at": "2025-01-10T...", "updated_at": "..."},
        ...     {"id": 2, "name": "교통", "created_at": "2025-01-10T...", "updated_at": "..."},
        ...     {"id": 3, "name": "통신", "created_at": "2025-01-10T...", "updated_at": "..."}
        ... ]

    Notes:
        - Uses CategoryRepository.get_all()
        - Categories ordered alphabetically by name
        - Categories are created automatically during file parsing
        - No create/update endpoints (categories auto-managed)
    """
    try:
        category_repo = CategoryRepository(db)
        categories = category_repo.get_all()

        return [
            CategoryResponse(
                id=cat['id'],
                name=cat['name'],
                created_at=cat['created_at'],
                updated_at=cat['updated_at']
            )
            for cat in categories
        ]
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to retrieve categories: {str(e)}"
        )
