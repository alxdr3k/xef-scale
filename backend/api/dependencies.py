"""
FastAPI dependency injection for authentication and database access.
Provides reusable dependencies for route handlers.
"""

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from typing import Optional
from enum import Enum
import sqlite3

from backend.core.security import verify_token
from backend.api.schemas import UserInfo
from src.db.connection import DatabaseConnection


# Security scheme for JWT bearer tokens
security = HTTPBearer()


# ============================================================================
# Workspace Role Enum
# ============================================================================


class WorkspaceRole(str, Enum):
    """
    Workspace role hierarchy with numeric levels for permission comparison.

    Roles (in ascending order of permissions):
    - MEMBER_READ: Can view workspace data (read-only access)
    - MEMBER_WRITE: Can add/edit transactions and categories
    - CO_OWNER: Can manage members and settings
    - OWNER: Full control including workspace deletion

    Examples:
        >>> role = WorkspaceRole.CO_OWNER
        >>> role.level > WorkspaceRole.MEMBER_WRITE.level  # True
        >>> WorkspaceRole.OWNER.level  # 4 (highest)
    """
    MEMBER_READ = "MEMBER_READ"
    MEMBER_WRITE = "MEMBER_WRITE"
    CO_OWNER = "CO_OWNER"
    OWNER = "OWNER"

    @property
    def level(self) -> int:
        """
        Get numeric level for role comparison.

        Returns:
            int: Numeric level (1=MEMBER_READ, 2=MEMBER_WRITE, 3=CO_OWNER, 4=OWNER)

        Examples:
            >>> WorkspaceRole.OWNER.level
            4
            >>> WorkspaceRole.MEMBER_READ.level
            1
            >>> WorkspaceRole.OWNER.level > WorkspaceRole.CO_OWNER.level
            True
        """
        levels = {
            'MEMBER_READ': 1,
            'MEMBER_WRITE': 2,
            'CO_OWNER': 3,
            'OWNER': 4
        }
        return levels.get(self.value, 0)


# ============================================================================
# Authentication Dependencies
# ============================================================================


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security)
) -> UserInfo:
    """
    Dependency to extract and validate current user from JWT token.

    Validates the JWT token from Authorization header and returns user information.
    Raises HTTP 401 if token is invalid or expired.

    Args:
        credentials: HTTP bearer credentials from Authorization header

    Returns:
        UserInfo: Current authenticated user information

    Raises:
        HTTPException: 401 if token is invalid, expired, or missing required fields

    Examples:
        >>> # In route handler
        >>> @router.get("/me")
        >>> async def get_me(current_user: UserInfo = Depends(get_current_user)):
        ...     return current_user

    Notes:
        - Token should be in format: "Bearer {jwt_token}"
        - Automatically extracts token from Authorization header
        - Validates signature and expiration
        - Returns user data from token payload
    """
    token = credentials.credentials

    # Verify and decode token
    payload = verify_token(token)
    if payload is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
            headers={"WWW-Authenticate": "Bearer"},
        )

    # Extract user information from payload
    user_id = payload.get("sub")
    email = payload.get("email")

    if not user_id or not email:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token payload",
            headers={"WWW-Authenticate": "Bearer"},
        )

    return UserInfo(
        id=user_id,
        email=email,
        name=payload.get("name"),
        picture=payload.get("picture")
    )


async def get_optional_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(
        HTTPBearer(auto_error=False)
    )
) -> Optional[UserInfo]:
    """
    Dependency to optionally extract current user from JWT token.

    Similar to get_current_user, but doesn't raise error if token is missing.
    Useful for endpoints that have different behavior for authenticated vs anonymous users.

    Args:
        credentials: Optional HTTP bearer credentials

    Returns:
        UserInfo if valid token provided, None otherwise

    Examples:
        >>> # In route handler
        >>> @router.get("/public")
        >>> async def public_endpoint(user: Optional[UserInfo] = Depends(get_optional_user)):
        ...     if user:
        ...         return f"Hello {user.email}"
        ...     return "Hello anonymous"

    Notes:
        - Returns None if no token provided or token is invalid
        - Does not raise authentication errors
        - Useful for public endpoints with optional authentication
    """
    if credentials is None:
        return None

    token = credentials.credentials
    payload = verify_token(token)

    if payload is None:
        return None

    user_id = payload.get("sub")
    email = payload.get("email")

    if not user_id or not email:
        return None

    return UserInfo(
        id=user_id,
        email=email,
        name=payload.get("name"),
        picture=payload.get("picture")
    )


# ============================================================================
# Database Dependencies
# ============================================================================


def get_db() -> sqlite3.Connection:
    """
    Dependency to get database connection.

    Provides singleton database connection for repository operations.
    Uses existing DatabaseConnection singleton pattern.

    Returns:
        sqlite3.Connection: Database connection with Row factory

    Examples:
        >>> # In route handler
        >>> @router.get("/transactions")
        >>> async def get_transactions(db: sqlite3.Connection = Depends(get_db)):
        ...     cursor = db.execute("SELECT * FROM transactions")
        ...     return cursor.fetchall()

    Notes:
        - Returns singleton connection (thread-safe)
        - Connection is already configured with:
            - WAL mode for concurrent reads
            - Foreign key constraints enabled
            - Row factory for dict-like access
        - No need to close connection (managed by singleton)
    """
    return DatabaseConnection.get_instance()


# ============================================================================
# Workspace Permission Dependencies
# ============================================================================


async def get_workspace_membership(
    workspace_id: int,
    current_user: UserInfo = Depends(get_current_user),
    db: sqlite3.Connection = Depends(get_db)
) -> dict:
    """
    Verify user has access to workspace and return membership details.

    Checks that the workspace exists and the current user is an active member.
    Returns membership details including role for permission checking.

    Args:
        workspace_id: The workspace to check access for
        current_user: Current authenticated user (from get_current_user dependency)
        db: Database connection (from get_db dependency)

    Returns:
        dict: Membership details with fields:
            - id: Membership ID
            - workspace_id: Workspace ID
            - user_id: User ID
            - role: User's role (OWNER, CO_OWNER, MEMBER_WRITE, MEMBER_READ)
            - is_active: Whether membership is active
            - joined_at: When user joined workspace
            - updated_at: Last update timestamp

    Raises:
        HTTPException: 404 if workspace not found
        HTTPException: 403 if user is not a member or membership is inactive

    Examples:
        >>> # In route handler
        >>> @router.get("/workspaces/{workspace_id}/transactions")
        >>> async def get_transactions(
        ...     workspace_id: int,
        ...     membership: dict = Depends(get_workspace_membership),
        ...     db: sqlite3.Connection = Depends(get_db)
        ... ):
        ...     # User has access, membership['role'] contains their role
        ...     return {"workspace_id": workspace_id, "role": membership['role']}

    Notes:
        - Automatically validates authentication via get_current_user dependency
        - Checks both workspace existence and user membership
        - Only active memberships are allowed
        - Use this as base dependency for all workspace-scoped endpoints
    """
    # Import here to avoid circular imports
    from src.db.repository import WorkspaceRepository, WorkspaceMembershipRepository

    # Check workspace exists
    workspace = WorkspaceRepository.get_by_id(db, workspace_id)
    if not workspace:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Workspace {workspace_id} not found"
        )

    # Check user membership
    membership = WorkspaceMembershipRepository.get_user_membership(
        db, workspace_id, int(current_user.id)
    )

    if not membership or not membership['is_active']:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You do not have access to this workspace"
        )

    return membership


def require_workspace_role(required_role: WorkspaceRole):
    """
    Factory function that creates a dependency to check minimum role requirement.

    Creates a reusable dependency that verifies the user has at least the specified
    role level in the workspace. Higher roles automatically satisfy lower role requirements
    (e.g., OWNER satisfies CO_OWNER requirement).

    Args:
        required_role: Minimum required role (OWNER, CO_OWNER, MEMBER_WRITE, MEMBER_READ)

    Returns:
        Callable: Async dependency function that can be used with Depends()

    Examples:
        >>> # Require CO_OWNER or higher
        >>> @router.post("/workspaces/{workspace_id}/members")
        >>> async def add_member(
        ...     workspace_id: int,
        ...     membership: dict = Depends(require_workspace_role(WorkspaceRole.CO_OWNER)),
        ...     db: sqlite3.Connection = Depends(get_db)
        ... ):
        ...     # Only CO_OWNER or OWNER can access this endpoint
        ...     return {"status": "member added"}

        >>> # Require OWNER only
        >>> @router.delete("/workspaces/{workspace_id}")
        >>> async def delete_workspace(
        ...     workspace_id: int,
        ...     membership: dict = Depends(require_workspace_role(WorkspaceRole.OWNER)),
        ...     db: sqlite3.Connection = Depends(get_db)
        ... ):
        ...     # Only OWNER can delete workspace
        ...     return {"status": "workspace deleted"}

        >>> # Require MEMBER_WRITE or higher (can modify data)
        >>> @router.post("/workspaces/{workspace_id}/transactions")
        >>> async def create_transaction(
        ...     workspace_id: int,
        ...     membership: dict = Depends(require_workspace_role(WorkspaceRole.MEMBER_WRITE)),
        ...     db: sqlite3.Connection = Depends(get_db)
        ... ):
        ...     # MEMBER_WRITE, CO_OWNER, or OWNER can create transactions
        ...     return {"status": "transaction created"}

    Notes:
        - Returns membership dict with role information if permission check passes
        - Role hierarchy: OWNER (4) > CO_OWNER (3) > MEMBER_WRITE (2) > MEMBER_READ (1)
        - Higher roles automatically satisfy lower role requirements
        - Raises 403 if user's role is insufficient
    """
    async def role_checker(
        workspace_id: int,
        membership: dict = Depends(get_workspace_membership)
    ) -> dict:
        """
        Check if user has required role or higher.

        Args:
            workspace_id: Workspace ID (automatically injected from path)
            membership: User's membership details (from get_workspace_membership)

        Returns:
            dict: Membership details if permission check passes

        Raises:
            HTTPException: 403 if user's role is insufficient
        """
        user_role = WorkspaceRole(membership['role'])

        if user_role.level < required_role.level:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Requires {required_role.value} role or higher. You have {user_role.value}."
            )

        return membership

    return role_checker


async def verify_api_access(
    current_user: UserInfo = Depends(get_current_user)
) -> UserInfo:
    """
    Dependency to verify user has API access.

    Currently just validates authentication, but can be extended
    to check user permissions, subscription status, rate limits, etc.

    Args:
        current_user: Current authenticated user from get_current_user

    Returns:
        UserInfo: Validated user with API access

    Raises:
        HTTPException: 403 if user doesn't have API access

    Examples:
        >>> # In route handler
        >>> @router.post("/admin/delete")
        >>> async def admin_delete(user: UserInfo = Depends(verify_api_access)):
        ...     # Only accessible to authenticated users with API access
        ...     return {"status": "deleted"}

    Notes:
        - Currently passes through all authenticated users
        - Can be extended to implement role-based access control
        - Can check database for user permissions/roles
        - Can implement rate limiting per user
    """
    # Future: Check database for user roles, permissions, etc.
    # For now, all authenticated users have API access
    return current_user
