"""
Pydantic schemas for API request/response validation.
Defines data transfer objects for all API endpoints.
"""

from pydantic import BaseModel, Field, field_validator
from typing import Optional, List, Dict, Any
from datetime import datetime


# ==================== Authentication Schemas ====================

class TokenResponse(BaseModel):
    """Response schema for authentication endpoints."""
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class UserInfo(BaseModel):
    """User information schema."""
    id: str
    email: str
    name: Optional[str] = None
    picture: Optional[str] = None


class GoogleAuthResponse(BaseModel):
    """Response schema for Google OAuth authentication."""
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    user: UserInfo


class GoogleAuthRequest(BaseModel):
    """Request schema for Google OAuth authentication."""
    credential: str = Field(..., description="Google ID token from Google Sign-In")


class LogoutResponse(BaseModel):
    """Response schema for logout endpoint."""
    message: str = "Logged out successfully"


# ==================== Transaction Schemas ====================

class TransactionBase(BaseModel):
    """Base transaction schema with common fields."""
    date: str = Field(..., description="Transaction date in yyyy.mm.dd format")
    category: str = Field(..., description="Category name (e.g., 식비, 교통)")
    merchant_name: str = Field(..., description="Merchant or item name")
    amount: int = Field(..., description="Transaction amount in KRW")
    institution: str = Field(..., description="Financial institution name")
    installment_months: Optional[int] = Field(None, description="Number of installment months")
    installment_current: Optional[int] = Field(None, description="Current installment number")
    original_amount: Optional[int] = Field(None, description="Original amount for installments")

    @field_validator("date")
    @classmethod
    def validate_date_format(cls, v: str) -> str:
        """Validate date is in yyyy.mm.dd format."""
        try:
            parts = v.split(".")
            if len(parts) != 3:
                raise ValueError("Date must be in yyyy.mm.dd format")
            year, month, day = map(int, parts)
            if not (1900 <= year <= 2100 and 1 <= month <= 12 and 1 <= day <= 31):
                raise ValueError("Invalid date values")
            return v
        except (ValueError, AttributeError):
            raise ValueError("Date must be in yyyy.mm.dd format")


class TransactionResponse(TransactionBase):
    """Transaction response schema with database fields."""
    id: int
    transaction_year: int
    transaction_month: int
    category_id: int
    institution_id: int
    file_id: Optional[int] = None
    row_number_in_file: Optional[int] = None
    created_at: str

    class Config:
        from_attributes = True


class TransactionListResponse(BaseModel):
    """Paginated transaction list response."""
    data: List[TransactionResponse]
    total: int
    page: int
    limit: int
    total_pages: int


class TransactionSummary(BaseModel):
    """Monthly/category summary response."""
    category: str
    total: int


class CategorySummary(BaseModel):
    """Category summary with ID, name, amount, and count."""
    category_id: int
    category_name: str
    amount: int
    count: int


class MonthlySummaryResponse(BaseModel):
    """Monthly spending summary by category."""
    year: int
    month: int
    total_amount: int
    transaction_count: int
    by_category: List[CategorySummary]


# ==================== Category Schemas ====================

class CategoryBase(BaseModel):
    """Base category schema."""
    name: str = Field(..., description="Category name (Korean)")


class CategoryResponse(CategoryBase):
    """Category response with database fields."""
    id: int
    created_at: str
    updated_at: str

    class Config:
        from_attributes = True


# ==================== Institution Schemas ====================

class InstitutionBase(BaseModel):
    """Base financial institution schema."""
    name: str = Field(..., description="Institution name (Korean)")
    institution_type: str = Field(..., description="Type: CARD, BANK, or PAY")
    display_name: Optional[str] = None


class InstitutionResponse(InstitutionBase):
    """Institution response with database fields."""
    id: int
    is_active: bool
    created_at: str
    updated_at: str

    class Config:
        from_attributes = True


# ==================== Parsing Session Schemas ====================

class ParsingSessionBase(BaseModel):
    """Base parsing session schema."""
    file_id: int
    parser_type: str
    total_rows_in_file: int


class ParsingSessionResponse(ParsingSessionBase):
    """Parsing session response with statistics."""
    id: int
    started_at: str
    completed_at: Optional[str] = None
    rows_saved: int
    rows_skipped: int
    rows_duplicate: int
    status: str
    error_message: Optional[str] = None
    validation_status: Optional[str] = None
    validation_notes: Optional[str] = None

    # Joined fields from processed_files and financial_institutions
    file_name: Optional[str] = None
    file_hash: Optional[str] = None
    institution_name: Optional[str] = None
    institution_type: Optional[str] = None

    class Config:
        from_attributes = True


class ParsingSessionListResponse(BaseModel):
    """Paginated parsing session list."""
    sessions: List[ParsingSessionResponse]
    total: int
    page: int
    page_size: int


# ==================== Skipped Transaction Schemas ====================

class SkippedTransactionResponse(BaseModel):
    """Skipped transaction response."""
    id: int
    session_id: int
    row_number: int
    skip_reason: str
    transaction_date: Optional[str] = None
    merchant_name: Optional[str] = None
    amount: Optional[int] = None
    original_amount: Optional[int] = None
    skip_details: Optional[str] = None
    column_data: Optional[Dict] = None

    class Config:
        from_attributes = True


# ==================== File Upload Schemas ====================

class FileUploadResponse(BaseModel):
    """File upload response."""
    file_id: int
    file_name: str
    file_size: int
    file_hash: str
    status: str
    message: str
    transaction_count: Optional[int] = None


# ==================== Query Parameter Schemas ====================

class TransactionQueryParams(BaseModel):
    """Query parameters for transaction filtering."""
    year: Optional[int] = Field(None, description="Filter by year")
    month: Optional[int] = Field(None, description="Filter by month (1-12)")
    category: Optional[str] = Field(None, description="Filter by category name")
    institution: Optional[str] = Field(None, description="Filter by institution name")
    page: int = Field(1, ge=1, description="Page number (1-indexed)")
    page_size: int = Field(50, ge=1, le=200, description="Items per page")

    @field_validator("month")
    @classmethod
    def validate_month(cls, v: Optional[int]) -> Optional[int]:
        """Validate month is between 1 and 12."""
        if v is not None and not (1 <= v <= 12):
            raise ValueError("Month must be between 1 and 12")
        return v


class SummaryQueryParams(BaseModel):
    """Query parameters for summary endpoints."""
    year: int = Field(..., description="Year for summary")
    month: int = Field(..., ge=1, le=12, description="Month for summary (1-12)")


# ==================== Error Response Schemas ====================

class ErrorResponse(BaseModel):
    """Standard error response."""
    error: str
    detail: Optional[str] = None
    code: Optional[str] = None


class ValidationErrorResponse(BaseModel):
    """Validation error response."""
    error: str = "Validation error"
    detail: List[Dict[str, Any]]
