"""
Pydantic schemas for API request/response validation.
Defines data transfer objects for all API endpoints.
"""

from pydantic import BaseModel, Field, field_validator, ConfigDict
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
    username: Optional[str] = None  # Optional field for logging/display


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
    notes: Optional[str] = None
    created_at: str

    # Workspace-related fields
    workspace_id: int
    is_allowance: bool = False
    uploaded_by: Optional[str] = None
    uploaded_by_user_id: Optional[int] = None

    model_config = ConfigDict(from_attributes=True)


class TransactionCreateRequest(BaseModel):
    """
    Request schema for creating a new transaction.

    Required fields:
    - workspace_id: Workspace ID where transaction will be created
    - date: Transaction date in yyyy.mm.dd format (Korean format)
    - category: Category name in Korean (e.g., 식비, 교통)
    - merchant_name: Merchant or item description (1-200 characters)
    - amount: Transaction amount in KRW (positive integer)
    - institution: Financial institution name in Korean

    Optional fields:
    - installment_months: Number of installment months (1-60)
    - installment_current: Current installment number (must be <= installment_months)
    - original_amount: Original amount for installment purchases
    - notes: Additional notes (max 500 characters)
    """
    workspace_id: int = Field(..., description="워크스페이스 ID")
    date: str = Field(..., description="거래 날짜 (yyyy.mm.dd 형식)")
    category: str = Field(..., description="카테고리 이름 (예: 식비, 교통)")
    merchant_name: str = Field(..., min_length=1, max_length=200, description="가맹점명 또는 거래 내역")
    amount: int = Field(..., gt=0, description="거래 금액 (원)")
    institution: str = Field(..., description="금융기관 이름 (예: 신한카드, 토스뱅크)")
    installment_months: Optional[int] = Field(None, ge=1, le=60, description="할부 개월 수 (1-60)")
    installment_current: Optional[int] = Field(None, ge=1, description="현재 할부 회차")
    original_amount: Optional[int] = Field(None, gt=0, description="할부 시 원 거래 금액")
    notes: Optional[str] = Field(None, max_length=500, description="메모 또는 추가 정보")

    @field_validator("date")
    @classmethod
    def validate_date_format(cls, v: str) -> str:
        """
        Validate date is in yyyy.mm.dd format and represents a valid calendar date.

        Args:
            v: Date string to validate

        Returns:
            Validated date string

        Raises:
            ValueError: If date format is invalid or date values are out of range
        """
        try:
            parts = v.split(".")
            if len(parts) != 3:
                raise ValueError("날짜는 yyyy.mm.dd 형식이어야 합니다")

            year, month, day = map(int, parts)

            # Validate year range
            if not (1900 <= year <= 2100):
                raise ValueError("연도는 1900-2100 범위이어야 합니다")

            # Validate month
            if not (1 <= month <= 12):
                raise ValueError("월은 1-12 범위이어야 합니다")

            # Validate day (basic check, not accounting for month-specific days)
            if not (1 <= day <= 31):
                raise ValueError("일은 1-31 범위이어야 합니다")

            # Additional validation for specific months
            if month in [4, 6, 9, 11] and day > 30:
                raise ValueError(f"{month}월은 30일까지만 있습니다")
            if month == 2:
                # Check leap year
                is_leap = (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0)
                max_day = 29 if is_leap else 28
                if day > max_day:
                    raise ValueError(f"{year}년 2월은 {max_day}일까지만 있습니다")

            return v
        except (ValueError, AttributeError) as e:
            if isinstance(e, ValueError) and "월" in str(e):
                raise e  # Re-raise our custom Korean error messages
            raise ValueError("날짜는 yyyy.mm.dd 형식이어야 합니다")

    @field_validator("installment_current")
    @classmethod
    def validate_installment_consistency(cls, v: Optional[int], info) -> Optional[int]:
        """
        Validate that installment_current is less than or equal to installment_months.

        Args:
            v: Current installment number
            info: Validation context containing other field values

        Returns:
            Validated installment_current value

        Raises:
            ValueError: If installment_current > installment_months
        """
        if v is not None:
            installment_months = info.data.get("installment_months")
            if installment_months is not None and v > installment_months:
                raise ValueError("현재 할부 회차는 총 할부 개월 수보다 클 수 없습니다")
        return v


class TransactionUpdateRequest(BaseModel):
    """
    Request schema for updating an existing transaction.

    All fields are optional to support partial updates.
    Only provided fields will be updated in the database.

    Field validation rules are the same as TransactionCreateRequest:
    - date: yyyy.mm.dd format validation
    - merchant_name: 1-200 characters when provided
    - amount: Must be positive when provided
    - installment_current: Must be <= installment_months when both provided
    """
    date: Optional[str] = Field(None, description="거래 날짜 (yyyy.mm.dd 형식)")
    category: Optional[str] = Field(None, description="카테고리 이름 (예: 식비, 교통)")
    merchant_name: Optional[str] = Field(None, min_length=1, max_length=200, description="가맹점명 또는 거래 내역")
    amount: Optional[int] = Field(None, gt=0, description="거래 금액 (원)")
    institution: Optional[str] = Field(None, description="금융기관 이름 (예: 신한카드, 토스뱅크)")
    installment_months: Optional[int] = Field(None, ge=1, le=60, description="할부 개월 수 (1-60)")
    installment_current: Optional[int] = Field(None, ge=1, description="현재 할부 회차")
    original_amount: Optional[int] = Field(None, gt=0, description="할부 시 원 거래 금액")
    notes: Optional[str] = Field(None, max_length=500, description="메모 또는 추가 정보")

    @field_validator("date")
    @classmethod
    def validate_date_format(cls, v: Optional[str]) -> Optional[str]:
        """
        Validate date is in yyyy.mm.dd format and represents a valid calendar date.

        Args:
            v: Date string to validate (None if not provided)

        Returns:
            Validated date string or None

        Raises:
            ValueError: If date format is invalid or date values are out of range
        """
        if v is None:
            return v

        try:
            parts = v.split(".")
            if len(parts) != 3:
                raise ValueError("날짜는 yyyy.mm.dd 형식이어야 합니다")

            year, month, day = map(int, parts)

            # Validate year range
            if not (1900 <= year <= 2100):
                raise ValueError("연도는 1900-2100 범위이어야 합니다")

            # Validate month
            if not (1 <= month <= 12):
                raise ValueError("월은 1-12 범위이어야 합니다")

            # Validate day (basic check)
            if not (1 <= day <= 31):
                raise ValueError("일은 1-31 범위이어야 합니다")

            # Additional validation for specific months
            if month in [4, 6, 9, 11] and day > 30:
                raise ValueError(f"{month}월은 30일까지만 있습니다")
            if month == 2:
                # Check leap year
                is_leap = (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0)
                max_day = 29 if is_leap else 28
                if day > max_day:
                    raise ValueError(f"{year}년 2월은 {max_day}일까지만 있습니다")

            return v
        except (ValueError, AttributeError) as e:
            if isinstance(e, ValueError) and "월" in str(e):
                raise e  # Re-raise our custom Korean error messages
            raise ValueError("날짜는 yyyy.mm.dd 형식이어야 합니다")

    @field_validator("installment_current")
    @classmethod
    def validate_installment_consistency(cls, v: Optional[int], info) -> Optional[int]:
        """
        Validate that installment_current is less than or equal to installment_months.

        Args:
            v: Current installment number (None if not provided)
            info: Validation context containing other field values

        Returns:
            Validated installment_current value or None

        Raises:
            ValueError: If installment_current > installment_months
        """
        if v is not None:
            installment_months = info.data.get("installment_months")
            if installment_months is not None and v > installment_months:
                raise ValueError("현재 할부 회차는 총 할부 개월 수보다 클 수 없습니다")
        return v


class TransactionCategoryUpdateRequest(BaseModel):
    """Request schema for updating transaction category only."""
    category: str = Field(..., description="카테고리 이름")


class TransactionDeleteResponse(BaseModel):
    """
    Response schema for successful transaction deletion.

    Returns the deleted transaction ID, confirmation message, and deletion timestamp.
    """
    id: int = Field(..., description="삭제된 거래 ID")
    message: str = Field(default="Transaction deleted successfully", description="삭제 확인 메시지")
    deleted_at: str = Field(..., description="삭제 시각 (ISO 8601 형식)")


class TransactionListResponse(BaseModel):
    """Paginated transaction list response with aggregated total."""
    data: List[TransactionResponse]
    total: int  # Total number of transactions (for pagination)
    page: int
    limit: int
    total_pages: int
    total_amount: int  # Total amount of ALL filtered transactions (not just current page)


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

    model_config = ConfigDict(from_attributes=True)


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

    model_config = ConfigDict(from_attributes=True)


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

    # Workspace and uploader fields (Phase 4.2)
    workspace_id: Optional[int] = None
    uploaded_by: Optional[str] = None  # Uploader name
    uploaded_by_user_id: Optional[int] = None

    model_config = ConfigDict(from_attributes=True)


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

    model_config = ConfigDict(from_attributes=True)


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


# ==================== Duplicate Confirmation Schemas ====================

class DuplicateConfirmationResponse(BaseModel):
    """Duplicate confirmation response with full transaction details."""
    id: int
    session_id: int
    new_transaction: Dict[str, Any]  # Parsed from JSON
    new_transaction_index: int
    existing_transaction: Dict[str, Any]  # Full transaction details
    confidence_score: int
    match_fields: List[str]
    difference_summary: Optional[str] = None
    status: str
    created_at: str
    expires_at: str

    model_config = ConfigDict(from_attributes=True)


class ConfirmationActionRequest(BaseModel):
    """Request schema for applying user decision to confirmation."""
    action: str = Field(..., description="User action: insert, skip, or merge")

    @field_validator("action")
    @classmethod
    def validate_action(cls, v: str) -> str:
        """Validate action is one of the allowed values."""
        valid_actions = {"insert", "skip", "merge"}
        if v not in valid_actions:
            raise ValueError(f"Action must be one of: {', '.join(valid_actions)}")
        return v


class BulkConfirmationResponse(BaseModel):
    """Response for bulk confirmation operation."""
    processed_count: int
    session_id: int


# ==================== Workspace Schemas ====================

class WorkspaceBase(BaseModel):
    """Base workspace fields."""
    name: str = Field(..., min_length=1, max_length=100, description="Workspace name")
    description: Optional[str] = Field(None, max_length=500, description="Workspace description")


class WorkspaceCreate(WorkspaceBase):
    """Schema for creating a workspace."""
    pass


class WorkspaceUpdate(BaseModel):
    """Schema for updating workspace (all fields optional)."""
    name: Optional[str] = Field(None, min_length=1, max_length=100, description="Workspace name")
    description: Optional[str] = Field(None, max_length=500, description="Workspace description")


class WorkspaceResponse(WorkspaceBase):
    """Schema for workspace response."""
    id: int
    created_by_user_id: int
    currency: str
    timezone: str
    is_active: bool
    member_count: int  # From repository join
    role: str  # User's role in this workspace
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class WorkspaceListResponse(BaseModel):
    """Schema for listing workspaces."""
    workspaces: List[WorkspaceResponse]


# ==================== Membership Schemas ====================

class MemberResponse(BaseModel):
    """Schema for workspace member."""
    user_id: int
    name: str
    email: str
    profile_picture_url: Optional[str]
    role: str  # OWNER, CO_OWNER, MEMBER_WRITE, MEMBER_READ
    joined_at: datetime

    model_config = ConfigDict(from_attributes=True)


class MemberListResponse(BaseModel):
    """Schema for listing members."""
    members: List[MemberResponse]


class MemberRoleUpdate(BaseModel):
    """Schema for updating member role."""
    role: str = Field(..., pattern="^(OWNER|CO_OWNER|MEMBER_WRITE|MEMBER_READ)$", description="New role for member")


# ==================== Invitation Schemas ====================

class InvitationCreate(BaseModel):
    """Schema for creating invitation."""
    role: str = Field(..., pattern="^(CO_OWNER|MEMBER_WRITE|MEMBER_READ)$", description="Role to assign (cannot be OWNER)")
    expires_in_days: int = Field(7, ge=1, le=90, description="Days until invitation expires (1-90)")
    max_uses: Optional[int] = Field(None, ge=1, description="Maximum number of uses (unlimited if null)")


class InvitationResponse(BaseModel):
    """Schema for invitation response."""
    id: int
    workspace_id: int
    token: str
    invitation_url: str  # Constructed URL (e.g., https://app.example.com/join/{token})
    role: str
    expires_at: datetime
    max_uses: Optional[int]
    current_uses: int
    is_active: bool
    created_by_user_id: int
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class InvitationListResponse(BaseModel):
    """Schema for listing invitations."""
    invitations: List[InvitationResponse]


class InvitationAcceptResponse(BaseModel):
    """Schema for invitation acceptance result."""
    workspace_id: int
    workspace_name: str
    role: str
    message: str


# ==================== Allowance Schemas ====================

class AllowanceMarkRequest(BaseModel):
    """Schema for marking transaction as allowance."""
    transaction_id: int = Field(..., description="Transaction ID to mark as allowance")
    notes: Optional[str] = Field(None, max_length=200, description="Optional notes about this allowance")


class AllowanceUnmarkRequest(BaseModel):
    """Schema for unmarking allowance (just transaction_id)."""
    transaction_id: int = Field(..., description="Transaction ID to unmark as allowance")


class AllowanceTransactionResponse(BaseModel):
    """Schema for allowance transaction."""
    id: int
    transaction_id: int
    # Transaction details
    transaction_date: str  # yyyy.mm.dd
    category_name: str
    merchant_name: str
    amount: int
    institution_name: str
    # Allowance-specific
    marked_at: datetime
    notes: Optional[str]

    model_config = ConfigDict(from_attributes=True)


class AllowanceListResponse(BaseModel):
    """Schema for listing allowances."""
    data: List[AllowanceTransactionResponse]
    total: int
    total_amount: int
    workspace: Dict[str, Any]  # {id, name}


class AllowanceSummaryResponse(BaseModel):
    """Schema for allowance summary."""
    year: int
    month: int
    total_amount: int
    transaction_count: int
    by_category: List[Dict[str, Any]]  # [{category_id, category_name, amount, count}]
