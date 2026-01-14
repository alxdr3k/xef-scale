"""
Workspace management API endpoints.

Provides full CRUD operations for workspaces with role-based access control.
Endpoints support multi-user collaboration with workspace ownership management.

Routes:
    GET    /api/workspaces                    - List user's workspaces
    POST   /api/workspaces                    - Create new workspace
    GET    /api/workspaces/{workspace_id}     - Get workspace detail
    PUT    /api/workspaces/{workspace_id}     - Update workspace (CO_OWNER+)
    DELETE /api/workspaces/{workspace_id}     - Delete workspace (OWNER only)
"""

from fastapi import APIRouter, Depends, HTTPException, Response, status
import sqlite3

from backend.api.dependencies import (
    get_current_user,
    get_db,
    get_workspace_membership,
    require_workspace_role,
    WorkspaceRole
)
from backend.api.schemas import (
    UserInfo,
    WorkspaceCreate,
    WorkspaceUpdate,
    WorkspaceResponse,
    WorkspaceListResponse
)
from src.db.repository import (
    WorkspaceRepository,
    WorkspaceMembershipRepository
)

router = APIRouter(tags=["Workspaces"])


@router.get("/workspaces", response_model=WorkspaceListResponse)
async def get_user_workspaces(
    current_user: UserInfo = Depends(get_current_user),
    db: sqlite3.Connection = Depends(get_db)
):
    """
    Get all workspaces where current user is a member.

    Returns a list of workspaces with user's role and member count for each workspace.
    Includes workspaces where the user has any role (OWNER, CO_OWNER, MEMBER_WRITE, MEMBER_READ).

    Returns:
        WorkspaceListResponse: List of workspaces with role and member information

    Examples:
        >>> GET /api/workspaces
        >>> Authorization: Bearer <token>
        {
          "workspaces": [
            {
              "id": 1,
              "name": "Family Expenses",
              "description": "Shared family budget tracking",
              "created_by_user_id": 1,
              "currency": "KRW",
              "timezone": "Asia/Seoul",
              "is_active": true,
              "member_count": 3,
              "role": "OWNER",
              "created_at": "2026-01-15T10:00:00Z",
              "updated_at": "2026-01-15T10:00:00Z"
            }
          ]
        }

    Notes:
        - Returns empty list if user has no workspaces
        - Workspaces ordered by created_at DESC (newest first)
        - Only returns active workspaces (is_active=True)
        - Includes member_count and user's role for each workspace
    """
    # Get workspaces with role and member_count from repository
    workspace_repo = WorkspaceRepository(db)
    workspaces = workspace_repo.get_user_workspaces(int(current_user.id))

    # Transform to response format (user_role -> role)
    formatted_workspaces = []
    for ws in workspaces:
        ws_dict = dict(ws)
        ws_dict['role'] = ws_dict.pop('user_role')  # Rename user_role to role
        formatted_workspaces.append(WorkspaceResponse(**ws_dict))

    return WorkspaceListResponse(workspaces=formatted_workspaces)


@router.post("/workspaces", response_model=WorkspaceResponse, status_code=status.HTTP_201_CREATED)
async def create_workspace(
    workspace_data: WorkspaceCreate,
    current_user: UserInfo = Depends(get_current_user),
    db: sqlite3.Connection = Depends(get_db)
):
    """
    Create a new workspace.

    The current user becomes the OWNER of the workspace automatically.
    Workspace is created with default settings (currency=KRW, timezone=Asia/Seoul).

    Args:
        workspace_data: Workspace name and optional description

    Returns:
        WorkspaceResponse: Created workspace with user as OWNER

    Raises:
        HTTPException: 500 if workspace creation fails

    Examples:
        >>> POST /api/workspaces
        >>> Authorization: Bearer <token>
        >>> Content-Type: application/json
        {
          "name": "Personal Budget",
          "description": "My personal expense tracking"
        }

        Response (201 Created):
        {
          "id": 5,
          "name": "Personal Budget",
          "description": "My personal expense tracking",
          "created_by_user_id": 2,
          "currency": "KRW",
          "timezone": "Asia/Seoul",
          "is_active": true,
          "member_count": 1,
          "role": "OWNER",
          "created_at": "2026-01-15T14:30:00Z",
          "updated_at": "2026-01-15T14:30:00Z"
        }

    Notes:
        - User automatically becomes OWNER (highest privilege)
        - Workspace created with is_active=True
        - Default currency: KRW (Korean Won)
        - Default timezone: Asia/Seoul
        - Member count starts at 1 (creator)
    """
    try:
        workspace_repo = WorkspaceRepository(db)
        membership_repo = WorkspaceMembershipRepository(db)

        # Create workspace
        workspace_id = workspace_repo.create(
            name=workspace_data.name,
            description=workspace_data.description or "",
            created_by_user_id=int(current_user.id)
        )

        # Add user as OWNER
        membership_repo.add_member(
            workspace_id=workspace_id,
            user_id=int(current_user.id),
            role='OWNER'
        )

        # Get workspace with all fields
        workspace = workspace_repo.get_by_id(workspace_id)
        if not workspace:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Workspace created but could not be retrieved"
            )

        # Add role and member_count
        workspace['role'] = 'OWNER'
        workspace['member_count'] = 1

        return WorkspaceResponse(**workspace)

    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to create workspace: {str(e)}"
        )


@router.get("/workspaces/{workspace_id}", response_model=WorkspaceResponse)
async def get_workspace(
    workspace_id: int,
    membership: dict = Depends(get_workspace_membership),
    db: sqlite3.Connection = Depends(get_db)
):
    """
    Get workspace details.

    Returns complete workspace information including member count.
    Requires user to be a member of the workspace (any role).

    Args:
        workspace_id: Workspace ID

    Returns:
        WorkspaceResponse: Workspace details with user's role

    Raises:
        HTTPException: 403 if user is not a member
        HTTPException: 404 if workspace not found

    Examples:
        >>> GET /api/workspaces/1
        >>> Authorization: Bearer <token>

        Response (200 OK):
        {
          "id": 1,
          "name": "Family Expenses",
          "description": "Shared family budget",
          "created_by_user_id": 1,
          "currency": "KRW",
          "timezone": "Asia/Seoul",
          "is_active": true,
          "member_count": 3,
          "role": "CO_OWNER",
          "created_at": "2026-01-01T00:00:00Z",
          "updated_at": "2026-01-15T10:00:00Z"
        }

    Notes:
        - Membership verified by get_workspace_membership dependency
        - Any role can view workspace details (MEMBER_READ, MEMBER_WRITE, CO_OWNER, OWNER)
        - Returns user's own role in the workspace
        - Includes active member count
    """
    workspace_repo = WorkspaceRepository(db)
    workspace = workspace_repo.get_by_id(workspace_id)
    if not workspace:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Workspace not found"
        )

    # Add role and member_count
    workspace['role'] = membership['role']
    workspace['member_count'] = workspace_repo.get_member_count(workspace_id)

    return WorkspaceResponse(**workspace)


@router.put("/workspaces/{workspace_id}", response_model=WorkspaceResponse)
async def update_workspace(
    workspace_id: int,
    updates: WorkspaceUpdate,
    membership: dict = Depends(require_workspace_role(WorkspaceRole.CO_OWNER)),
    db: sqlite3.Connection = Depends(get_db)
):
    """
    Update workspace name and/or description.

    Requires CO_OWNER or OWNER role. Supports partial updates (only provided fields are updated).

    Args:
        workspace_id: Workspace ID
        updates: Fields to update (name and/or description)

    Returns:
        WorkspaceResponse: Updated workspace

    Raises:
        HTTPException: 400 if no fields provided to update
        HTTPException: 403 if user lacks CO_OWNER role
        HTTPException: 404 if workspace not found

    Examples:
        >>> PUT /api/workspaces/1
        >>> Authorization: Bearer <token>
        >>> Content-Type: application/json
        {
          "name": "Updated Family Budget"
        }

        Response (200 OK):
        {
          "id": 1,
          "name": "Updated Family Budget",
          "description": "Shared family budget",
          "created_by_user_id": 1,
          "currency": "KRW",
          "timezone": "Asia/Seoul",
          "is_active": true,
          "member_count": 3,
          "role": "CO_OWNER",
          "created_at": "2026-01-01T00:00:00Z",
          "updated_at": "2026-01-15T15:00:00Z"
        }

    Notes:
        - Requires CO_OWNER or OWNER role (MEMBER_WRITE and MEMBER_READ cannot update)
        - Only name and description can be updated
        - Cannot update: currency, timezone, created_by_user_id
        - Partial updates supported (provide only fields you want to change)
        - Empty updates return 400 Bad Request
        - Updated_at timestamp automatically updated
    """
    workspace_repo = WorkspaceRepository(db)

    # Only update non-None fields
    update_dict = updates.model_dump(exclude_unset=True)

    if not update_dict:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No fields to update"
        )

    success = workspace_repo.update(workspace_id, update_dict)
    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Workspace not found"
        )

    # Get updated workspace
    workspace = workspace_repo.get_by_id(workspace_id)
    if not workspace:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Workspace not found"
        )

    workspace['role'] = membership['role']
    workspace['member_count'] = workspace_repo.get_member_count(workspace_id)

    return WorkspaceResponse(**workspace)


@router.delete("/workspaces/{workspace_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_workspace(
    workspace_id: int,
    membership: dict = Depends(require_workspace_role(WorkspaceRole.OWNER)),
    db: sqlite3.Connection = Depends(get_db)
):
    """
    Delete workspace (soft delete).

    Requires OWNER role. Cannot delete if multiple OWNERs exist - ownership must be
    transferred first. Sets is_active=False (soft delete).

    Args:
        workspace_id: Workspace ID

    Returns:
        204 No Content on success

    Raises:
        HTTPException: 400 if multiple OWNERs exist
        HTTPException: 403 if user is not OWNER
        HTTPException: 404 if workspace not found

    Examples:
        >>> DELETE /api/workspaces/1
        >>> Authorization: Bearer <token>

        Response (204 No Content): <empty body>

        Error response (400 Bad Request):
        {
          "detail": "Cannot delete workspace with multiple OWNERs. Transfer ownership first."
        }

    Notes:
        - OWNER role required (CO_OWNER cannot delete)
        - Soft delete: Sets is_active=False (data preserved)
        - CASCADE deletes related data:
          - Workspace memberships
          - Pending invitations
          - Allowance transaction markers
        - Cannot delete if multiple OWNERs exist
        - To delete: First transfer OWNER role or remove other OWNERs
        - Updated_at timestamp automatically updated
    """
    workspace_repo = WorkspaceRepository(db)
    membership_repo = WorkspaceMembershipRepository(db)

    # Check if other OWNERs exist
    owner_count = membership_repo.get_owner_count(workspace_id)
    if owner_count > 1:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot delete workspace with multiple OWNERs. Transfer ownership first."
        )

    # Soft delete workspace
    success = workspace_repo.delete(workspace_id)
    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Workspace not found"
        )

    return Response(status_code=status.HTTP_204_NO_CONTENT)
