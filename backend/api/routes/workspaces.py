"""
Workspace management API endpoints.

Provides full CRUD operations for workspaces with role-based access control.
Endpoints support multi-user collaboration with workspace ownership management.

Routes:
    GET    /api/workspaces                              - List user's workspaces
    POST   /api/workspaces                              - Create new workspace
    GET    /api/workspaces/{workspace_id}               - Get workspace detail
    PUT    /api/workspaces/{workspace_id}               - Update workspace (CO_OWNER+)
    DELETE /api/workspaces/{workspace_id}               - Delete workspace (OWNER only)
    GET    /api/workspaces/{workspace_id}/members       - List workspace members
    PATCH  /api/workspaces/{workspace_id}/members/{user_id}/role  - Update member role (CO_OWNER+)
    DELETE /api/workspaces/{workspace_id}/members/{user_id}       - Remove member (CO_OWNER+)
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
    WorkspaceListResponse,
    MemberResponse,
    MemberListResponse,
    MemberRoleUpdate
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


# ==================== Membership Management Endpoints ====================


@router.get("/workspaces/{workspace_id}/members", response_model=MemberListResponse)
async def get_workspace_members(
    workspace_id: int,
    membership: dict = Depends(get_workspace_membership),
    db: sqlite3.Connection = Depends(get_db)
):
    """
    Get all active members of workspace.

    Requires: Any role (membership verified)

    Returns members ordered by role hierarchy (OWNER first), then joined_at.

    Args:
        workspace_id: Workspace ID

    Returns:
        MemberListResponse: List of members with user details and roles

    Raises:
        HTTPException: 403 if user is not a member

    Examples:
        >>> GET /api/workspaces/1/members
        >>> Authorization: Bearer <token>

        Response (200 OK):
        {
          "members": [
            {
              "user_id": 1,
              "name": "Alice",
              "email": "alice@example.com",
              "profile_picture_url": "https://example.com/avatar1.jpg",
              "role": "OWNER",
              "joined_at": "2026-01-01T00:00:00Z"
            },
            {
              "user_id": 2,
              "name": "Bob",
              "email": "bob@example.com",
              "profile_picture_url": null,
              "role": "CO_OWNER",
              "joined_at": "2026-01-02T00:00:00Z"
            },
            {
              "user_id": 3,
              "name": "Charlie",
              "email": "charlie@example.com",
              "profile_picture_url": null,
              "role": "MEMBER_WRITE",
              "joined_at": "2026-01-05T00:00:00Z"
            }
          ]
        }

    Notes:
        - Any member can view the member list (MEMBER_READ, MEMBER_WRITE, CO_OWNER, OWNER)
        - Members ordered by role hierarchy (OWNER > CO_OWNER > MEMBER_WRITE > MEMBER_READ)
        - Within same role, ordered by joined_at ASC (earliest first)
        - Only returns active members (is_active=True)
    """
    membership_repo = WorkspaceMembershipRepository(db)
    members = membership_repo.get_workspace_members(workspace_id)
    return MemberListResponse(members=members)


@router.patch("/workspaces/{workspace_id}/members/{user_id}/role", response_model=MemberResponse)
async def update_member_role(
    workspace_id: int,
    user_id: int,
    role_update: MemberRoleUpdate,
    membership: dict = Depends(require_workspace_role(WorkspaceRole.CO_OWNER)),
    current_user: UserInfo = Depends(get_current_user),
    db: sqlite3.Connection = Depends(get_db)
):
    """
    Update member's role.

    Requires: CO_OWNER or OWNER

    Permission rules:
    - OWNER can change any role
    - CO_OWNER can only change MEMBER_READ/MEMBER_WRITE roles (not OWNER/CO_OWNER)
    - Cannot change your own role
    - Cannot demote yourself if you're the last OWNER

    Args:
        workspace_id: Workspace ID
        user_id: User to modify
        role_update: New role (OWNER, CO_OWNER, MEMBER_WRITE, MEMBER_READ)

    Returns:
        MemberResponse: Updated member information

    Raises:
        HTTPException: 400 if invalid role change (trying to change own role, last OWNER, etc.)
        HTTPException: 403 if insufficient permissions (CO_OWNER trying to modify OWNER)
        HTTPException: 404 if member not found

    Examples:
        >>> PATCH /api/workspaces/1/members/3/role
        >>> Authorization: Bearer <token>
        >>> Content-Type: application/json
        {
          "role": "MEMBER_WRITE"
        }

        Response (200 OK):
        {
          "user_id": 3,
          "name": "Charlie",
          "email": "charlie@example.com",
          "profile_picture_url": null,
          "role": "MEMBER_WRITE",
          "joined_at": "2026-01-05T00:00:00Z"
        }

        Error response (400 Bad Request):
        {
          "detail": "Cannot change your own role"
        }

        Error response (403 Forbidden):
        {
          "detail": "CO_OWNER cannot modify OWNER or CO_OWNER roles"
        }

    Notes:
        - Self-modification prevented (cannot change your own role)
        - Last OWNER protection (cannot demote if only OWNER remaining)
        - CO_OWNER permission restrictions enforced
        - Role hierarchy: OWNER > CO_OWNER > MEMBER_WRITE > MEMBER_READ
    """
    membership_repo = WorkspaceMembershipRepository(db)

    # Check if trying to change own role
    if user_id == int(current_user.id):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot change your own role"
        )

    # Get target member
    target_member = membership_repo.get_user_membership(workspace_id, user_id)
    if not target_member or not target_member['is_active']:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Member not found"
        )

    # Permission check: CO_OWNER cannot modify OWNER/CO_OWNER roles
    if membership['role'] == 'CO_OWNER':
        target_role = WorkspaceRole(target_member['role'])
        new_role = WorkspaceRole(role_update.role)

        if target_role in [WorkspaceRole.OWNER, WorkspaceRole.CO_OWNER]:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="CO_OWNER cannot modify OWNER or CO_OWNER roles"
            )

        if new_role in [WorkspaceRole.OWNER, WorkspaceRole.CO_OWNER]:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="CO_OWNER cannot promote members to OWNER or CO_OWNER"
            )

    # If demoting OWNER, check it's not the last OWNER
    if target_member['role'] == 'OWNER' and role_update.role != 'OWNER':
        owner_count = membership_repo.get_owner_count(workspace_id)
        if owner_count <= 1:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Cannot demote the last OWNER. Promote another member to OWNER first."
            )

    # Update role
    success = membership_repo.update_role(workspace_id, user_id, role_update.role)
    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Failed to update role"
        )

    # Get updated member (join with users table)
    members = membership_repo.get_workspace_members(workspace_id)
    member_data = next((m for m in members if m['user_id'] == user_id), None)

    if not member_data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Member not found after update"
        )

    return MemberResponse(**member_data)


@router.delete("/workspaces/{workspace_id}/members/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
async def remove_member(
    workspace_id: int,
    user_id: int,
    membership: dict = Depends(require_workspace_role(WorkspaceRole.CO_OWNER)),
    current_user: UserInfo = Depends(get_current_user),
    db: sqlite3.Connection = Depends(get_db)
):
    """
    Remove member from workspace (soft delete).

    Requires: CO_OWNER or OWNER

    Rules:
    - OWNER can remove anyone (except themselves if last OWNER)
    - CO_OWNER can only remove MEMBER_READ/MEMBER_WRITE
    - Cannot remove yourself if you're the last OWNER
    - Removing yourself = leaving workspace

    Args:
        workspace_id: Workspace ID
        user_id: User to remove

    Returns:
        204 No Content on success

    Raises:
        HTTPException: 400 if cannot remove last OWNER
        HTTPException: 403 if insufficient permissions
        HTTPException: 404 if member not found

    Examples:
        >>> DELETE /api/workspaces/1/members/3
        >>> Authorization: Bearer <token>

        Response (204 No Content): <empty body>

        Error response (400 Bad Request):
        {
          "detail": "Cannot remove the last OWNER. Promote another member to OWNER first."
        }

        Error response (403 Forbidden):
        {
          "detail": "CO_OWNER cannot remove OWNER or CO_OWNER members"
        }

    Notes:
        - Soft delete: Sets is_active=False (preserves history)
        - Last OWNER protection enforced
        - CO_OWNER permission restrictions enforced
        - Self-removal allowed (leaving workspace) if not last OWNER
    """
    membership_repo = WorkspaceMembershipRepository(db)

    # Get target member
    target_member = membership_repo.get_user_membership(workspace_id, user_id)
    if not target_member or not target_member['is_active']:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Member not found"
        )

    # Permission check: CO_OWNER cannot remove OWNER/CO_OWNER
    if membership['role'] == 'CO_OWNER':
        target_role = WorkspaceRole(target_member['role'])
        if target_role in [WorkspaceRole.OWNER, WorkspaceRole.CO_OWNER]:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="CO_OWNER cannot remove OWNER or CO_OWNER members"
            )

    # Check if removing last OWNER
    if target_member['role'] == 'OWNER':
        owner_count = membership_repo.get_owner_count(workspace_id)
        if owner_count <= 1:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Cannot remove the last OWNER. Promote another member to OWNER first."
            )

    # Remove member
    success = membership_repo.remove_member(workspace_id, user_id)
    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Failed to remove member"
        )

    return Response(status_code=status.HTTP_204_NO_CONTENT)
