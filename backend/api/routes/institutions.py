"""
Financial institution routes for managing banks, cards, and payment services.
Provides read-only access to institutions.
"""

from fastapi import APIRouter, Depends, HTTPException, status
from typing import List
import sqlite3

from backend.api.schemas import InstitutionResponse, ErrorResponse, UserInfo
from backend.api.dependencies import get_current_user, get_db
from src.db.repository import InstitutionRepository

router = APIRouter(prefix="/institutions", tags=["Institutions"])


@router.get(
    "",
    response_model=List[InstitutionResponse],
    responses={
        401: {"model": ErrorResponse, "description": "Not authenticated"}
    }
)
async def get_institutions(
    db: sqlite3.Connection = Depends(get_db),
    current_user: UserInfo = Depends(get_current_user)
):
    """
    Get all financial institutions.

    Returns list of all active financial institutions (banks, cards, payment services)
    sorted alphabetically by name. Only active institutions are returned.

    Args:
        db: Database connection from dependency
        current_user: Current authenticated user

    Returns:
        List of InstitutionResponse objects with id, name, type, and status

    Examples:
        >>> # Get all institutions
        >>> GET /api/institutions

        >>> # Response
        >>> [
        ...     {
        ...         "id": 1,
        ...         "name": "하나카드",
        ...         "institution_type": "CARD",
        ...         "display_name": "하나카드",
        ...         "is_active": true,
        ...         "created_at": "2025-01-10T...",
        ...         "updated_at": "..."
        ...     },
        ...     {
        ...         "id": 2,
        ...         "name": "토스뱅크",
        ...         "institution_type": "BANK",
        ...         "display_name": "토스뱅크",
        ...         "is_active": true,
        ...         "created_at": "2025-01-10T...",
        ...         "updated_at": "..."
        ...     }
        ... ]

    Notes:
        - Uses InstitutionRepository.get_all()
        - Only returns active institutions (is_active=true)
        - Institutions ordered alphabetically by name
        - Institutions created automatically during file parsing
        - Types: CARD (credit cards), BANK (banks), PAY (payment services)
    """
    try:
        institution_repo = InstitutionRepository(db)
        institutions = institution_repo.get_all()

        return [
            InstitutionResponse(
                id=inst['id'],
                name=inst['name'],
                institution_type=inst['institution_type'],
                display_name=inst['display_name'],
                is_active=bool(inst['is_active']),
                created_at=inst['created_at'],
                updated_at=inst['updated_at']
            )
            for inst in institutions
        ]
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to retrieve institutions: {str(e)}"
        )
