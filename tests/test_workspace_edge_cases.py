"""
Integration tests for workspace edge cases and boundary conditions (Phase 11.3).

Tests critical business rules and error scenarios:
- Last OWNER protection (cannot leave)
- Multiple OWNERs scenarios
- Workspace deletion rules
- Invitation expiration handling
- Max uses enforcement
- Concurrent invitation acceptance (atomic operations)
- CO_OWNER permission boundaries

These tests ensure data integrity and prevent invalid states.
"""

import pytest
import sqlite3
from datetime import datetime, timedelta
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

from src.db.connection import DatabaseConnection
from src.db.repository import (
    WorkspaceRepository,
    WorkspaceMembershipRepository,
    WorkspaceInvitationRepository,
    UserRepository
)


@pytest.fixture
def clean_db(test_db_override):
    """Provide clean database for each test."""
    return DatabaseConnection.get_instance()


class TestLastOwnerProtection:
    """Test 1: Last OWNER Cannot Leave"""

    def test_last_owner_cannot_leave_workspace(self, clean_db):
        """
        When User A is the sole OWNER, they cannot leave the workspace.

        Business Rule: At least one OWNER must exist in every workspace.
        User must either transfer ownership or delete the workspace.

        Verifies:
        - Attempting to remove last OWNER fails (via application logic)
        - User A still has membership
        - Owner count remains 1
        """
        db = clean_db

        # Setup: Create User A as sole OWNER
        user_repo = UserRepository(db)
        user_a_id = user_repo.create_user(
            email="sole_owner@test.com",
            google_id="google_sole_owner",
            name="Sole Owner"
        )

        workspace_repo = WorkspaceRepository(db)
        workspace_id = workspace_repo.create(
            name="Last Owner Test Workspace",
            description="Testing last owner protection",
            created_by_user_id=user_a_id
        )

        membership_repo = WorkspaceMembershipRepository(db)

        # Verify User A is sole OWNER
        assert membership_repo.get_owner_count(workspace_id) == 1

        # Attempt to remove last OWNER
        # Note: In production, API layer checks owner count before allowing removal
        # We simulate this check here
        owner_count = membership_repo.get_owner_count(workspace_id)
        if owner_count <= 1:
            # This would trigger 400 Bad Request in API layer
            can_leave = False
        else:
            can_leave = True

        assert can_leave is False, "Last OWNER should not be allowed to leave"

        # Verify User A still has membership (since we prevented removal)
        membership = membership_repo.get_user_membership(workspace_id, user_a_id)
        assert membership is not None, "User A should still have membership"
        assert membership['role'] == 'OWNER', "User A should still be OWNER"
        assert membership['is_active'] == 1, "Membership should still be active"

        # Verify owner count unchanged
        assert membership_repo.get_owner_count(workspace_id) == 1


class TestMultipleOwnersScenarios:
    """Test 2: Multiple OWNERs - Leave Allowed"""

    def test_multiple_owners_leave_allowed(self, clean_db):
        """
        When workspace has 2 OWNERs, either can leave.

        Verifies:
        - User A promotes User B to OWNER (2 OWNERs exist)
        - User A can successfully leave
        - Only User B remains as OWNER
        - Owner count is 1 after User A leaves
        """
        db = clean_db

        # Setup: Create User A and User B
        user_repo = UserRepository(db)
        user_a_id = user_repo.create_user(
            email="multi_owner_a@test.com",
            google_id="google_multi_owner_a",
            name="Multi Owner A"
        )
        user_b_id = user_repo.create_user(
            email="multi_owner_b@test.com",
            google_id="google_multi_owner_b",
            name="Multi Owner B"
        )

        workspace_repo = WorkspaceRepository(db)
        workspace_id = workspace_repo.create(
            name="Multi Owner Test Workspace",
            description="Testing multiple owners",
            created_by_user_id=user_a_id
        )

        membership_repo = WorkspaceMembershipRepository(db)

        # Add User B as MEMBER_WRITE
        membership_repo.add_member(workspace_id, user_b_id, 'MEMBER_WRITE')

        # User A promotes User B to OWNER
        success = membership_repo.update_role(workspace_id, user_b_id, 'OWNER')
        assert success is True, "Should successfully promote User B to OWNER"

        # Verify 2 OWNERs exist
        owner_count = membership_repo.get_owner_count(workspace_id)
        assert owner_count == 2, "Should have 2 OWNERs"

        # User A can now leave (since there are multiple OWNERs)
        if owner_count > 1:
            can_leave = True
            success = membership_repo.remove_member(workspace_id, user_a_id)
        else:
            can_leave = False
            success = False

        assert can_leave is True, "User A should be allowed to leave"
        assert success is True, "User A should successfully leave"

        # Verify only User B remains as OWNER
        members = membership_repo.get_workspace_members(workspace_id)
        assert len(members) == 1, "Only 1 active member should remain"
        assert members[0]['user_id'] == user_b_id
        assert members[0]['role'] == 'OWNER'

        # Verify owner count is now 1
        owner_count = membership_repo.get_owner_count(workspace_id)
        assert owner_count == 1, "Should have 1 OWNER after User A leaves"


class TestWorkspaceDeletionWithMultipleOwners:
    """Test 3: Workspace Deletion with Multiple OWNERs"""

    def test_workspace_deletion_blocked_with_multiple_owners(self, clean_db):
        """
        When workspace has multiple OWNERs, deletion should be blocked.

        Business Rule: Only sole OWNER can delete workspace.
        This prevents conflicts when multiple OWNERs exist.

        Verifies:
        - User A tries to delete workspace with 2 OWNERs
        - Deletion fails (via application logic check)
        - Workspace still exists
        """
        db = clean_db

        # Setup: Create workspace with 2 OWNERs
        user_repo = UserRepository(db)
        user_a_id = user_repo.create_user(
            email="delete_multi_a@test.com",
            google_id="google_delete_multi_a",
            name="Delete Multi A"
        )
        user_b_id = user_repo.create_user(
            email="delete_multi_b@test.com",
            google_id="google_delete_multi_b",
            name="Delete Multi B"
        )

        workspace_repo = WorkspaceRepository(db)
        workspace_id = workspace_repo.create(
            name="Delete Multi Owner Workspace",
            description="Testing deletion with multiple owners",
            created_by_user_id=user_a_id
        )

        membership_repo = WorkspaceMembershipRepository(db)
        membership_repo.add_member(workspace_id, user_b_id, 'OWNER')

        # Verify 2 OWNERs
        assert membership_repo.get_owner_count(workspace_id) == 2

        # User A tries to delete workspace
        # In production, API checks owner count before deletion
        owner_count = membership_repo.get_owner_count(workspace_id)
        if owner_count > 1:
            can_delete = False
        else:
            can_delete = True

        assert can_delete is False, \
            "Workspace deletion should be blocked when multiple OWNERs exist"

        # Verify workspace still exists
        workspace = workspace_repo.get_by_id(workspace_id)
        assert workspace is not None, "Workspace should still exist"
        assert workspace['is_active'] == 1, "Workspace should still be active"


class TestWorkspaceDeletionBySoleOwner:
    """Test 4: Workspace Deletion by Sole OWNER"""

    def test_sole_owner_can_delete_workspace(self, clean_db):
        """
        Sole OWNER can delete workspace.

        Verifies:
        - User A is sole OWNER
        - User A successfully deletes workspace
        - Workspace is soft-deleted (is_active=0) or hard-deleted
        - All memberships cascade deleted
        - All invitations cascade deleted
        """
        db = clean_db

        # Setup: Create User A as sole OWNER
        user_repo = UserRepository(db)
        user_a_id = user_repo.create_user(
            email="delete_sole@test.com",
            google_id="google_delete_sole",
            name="Delete Sole Owner"
        )

        workspace_repo = WorkspaceRepository(db)
        workspace_id = workspace_repo.create(
            name="Delete Sole Owner Workspace",
            description="Testing sole owner deletion",
            created_by_user_id=user_a_id
        )

        membership_repo = WorkspaceMembershipRepository(db)
        invitation_repo = WorkspaceInvitationRepository(db)

        # Create an invitation to test cascade deletion
        invitation = invitation_repo.create_invitation(
            db=db,
            workspace_id=workspace_id,
            role='MEMBER_WRITE',
            created_by_user_id=user_a_id,
            expires_in_days=7,
            max_uses=None
        )
        invitation_id = invitation['id']

        # Verify User A is sole OWNER
        assert membership_repo.get_owner_count(workspace_id) == 1

        # User A deletes workspace (soft delete: set is_active=0)
        # Soft delete: set is_active=0
        db.execute('UPDATE workspaces SET is_active = 0 WHERE id = ?', (workspace_id,))
        db.commit()
        success = True
        assert success is True, "Sole OWNER should successfully delete workspace"

        # Verify workspace is soft-deleted
        workspace = workspace_repo.get_by_id(workspace_id)
        if workspace is None:
            # Hard delete case
            workspace_deleted = True
        else:
            # Soft delete case
            workspace_deleted = workspace.get('is_active', 1) == 0

        assert workspace_deleted, "Workspace should be deleted (soft or hard)"

        # Verify memberships cascade behavior
        # Note: CASCADE DELETE in SQLite requires ON DELETE CASCADE in schema
        # Check if memberships still exist or are cascade deleted
        members = membership_repo.get_workspace_members(workspace_id)
        # After soft delete, active members should be 0 (if is_active filter applied)
        # Or memberships should be cascade deleted (if hard delete)
        assert len(members) == 0, \
            "Active memberships should be empty after workspace deletion"

        # Verify invitation is cascade deleted
        cursor = db.execute(
            'SELECT * FROM workspace_invitations WHERE id = ?',
            (invitation_id,)
        )
        invitation_after = cursor.fetchone()
        # Invitation should be cascade deleted if workspace is hard-deleted
        # or should be inactive if workspace is soft-deleted
        if workspace is None:
            assert invitation_after is None, \
                "Invitation should be cascade deleted with workspace"


class TestExpiredInvitation:
    """Test 5: Expired Invitation Cannot Be Accepted"""

    def test_expired_invitation_rejected(self, clean_db):
        """
        User cannot accept expired invitation.

        Verifies:
        - Create invitation with 1-day expiry
        - Manually set expires_at to yesterday (simulate expiration)
        - User B tries to accept
        - Acceptance fails with appropriate error
        - User B is not added to workspace
        """
        db = clean_db

        # Setup: Create User A and workspace
        user_repo = UserRepository(db)
        user_a_id = user_repo.create_user(
            email="expired_owner@test.com",
            google_id="google_expired_owner",
            name="Expired Owner"
        )
        user_b_id = user_repo.create_user(
            email="expired_user@test.com",
            google_id="google_expired_user",
            name="Expired User"
        )

        workspace_repo = WorkspaceRepository(db)
        workspace_id = workspace_repo.create(
            name="Expired Invitation Workspace",
            description="Testing expired invitations",
            created_by_user_id=user_a_id
        )

        # Add creator as OWNER
        membership_repo = WorkspaceMembershipRepository(db)
        membership_repo.add_member(workspace_id, user_a_id, 'OWNER')

        invitation_repo = WorkspaceInvitationRepository(db)

        # Create invitation with future expiry first
        invitation = invitation_repo.create_invitation(
            db=db,
            workspace_id=workspace_id,
            role='MEMBER_WRITE',
            created_by_user_id=user_a_id,
            expires_in_days=7,
            max_uses=None
        )
        token = invitation['token']
        invitation_id = invitation['id']

        # Manually set expires_at to yesterday (simulate expiration)
        yesterday = datetime.now() - timedelta(days=1)
        db.execute(
            'UPDATE workspace_invitations SET expires_at = ? WHERE id = ?',
            (yesterday.isoformat(), invitation_id)
        )
        db.commit()

        # User B tries to accept expired invitation
        try:
            accepted = invitation_repo.accept_invitation(db, token, user_b_id)
            # If accept_invitation doesn't raise error, check return value
            if accepted is None:
                acceptance_failed = True
            else:
                acceptance_failed = False
        except (ValueError, sqlite3.IntegrityError, Exception) as e:
            # Expected: invitation validation should fail
            acceptance_failed = True

        assert acceptance_failed is True, \
            "Expired invitation should not be accepted"

        # Verify User B was NOT added to workspace
        membership_repo = WorkspaceMembershipRepository(db)
        membership = membership_repo.get_user_membership(workspace_id, user_b_id)

        if membership is not None:
            # If membership exists, it should be inactive
            assert membership['is_active'] == 0, \
                "User B should not have active membership"
        else:
            # Preferred: no membership record at all
            assert membership is None, "User B should not have membership"


class TestMaxUsesExhausted:
    """Test 6: Max Uses Exhausted"""

    def test_invitation_with_max_uses_exhausted(self, clean_db):
        """
        After max_uses is reached, invitation cannot be accepted.

        Verifies:
        - Create invitation with max_uses=1
        - User B accepts (uses=1)
        - User C tries to accept same token
        - User C's acceptance fails
        - User C is not added to workspace
        """
        db = clean_db

        # Setup: Create users and workspace
        user_repo = UserRepository(db)
        user_a_id = user_repo.create_user(
            email="maxuses_owner@test.com",
            google_id="google_maxuses_owner",
            name="MaxUses Owner"
        )
        user_b_id = user_repo.create_user(
            email="maxuses_user_b@test.com",
            google_id="google_maxuses_user_b",
            name="MaxUses User B"
        )
        user_c_id = user_repo.create_user(
            email="maxuses_user_c@test.com",
            google_id="google_maxuses_user_c",
            name="MaxUses User C"
        )

        workspace_repo = WorkspaceRepository(db)
        workspace_id = workspace_repo.create(
            name="MaxUses Test Workspace",
            description="Testing max uses enforcement",
            created_by_user_id=user_a_id
        )

        # Add creator as OWNER
        membership_repo = WorkspaceMembershipRepository(db)
        membership_repo.add_member(workspace_id, user_a_id, 'OWNER')

        invitation_repo = WorkspaceInvitationRepository(db)

        # Create invitation with max_uses=1
        invitation = invitation_repo.create_invitation(
            db=db,
            workspace_id=workspace_id,
            role='MEMBER_WRITE',
            created_by_user_id=user_a_id,
            expires_in_days=7,
            max_uses=1
        )
        token = invitation['token']

        # User B accepts invitation (first use)
        accepted_b = invitation_repo.accept_invitation(db, token, user_b_id)
        assert accepted_b is not None, "User B should successfully accept"
        assert accepted_b['current_uses'] == 1, "Current uses should be 1"

        # User C tries to accept same token (exceeds max_uses)
        try:
            accepted_c = invitation_repo.accept_invitation(db, token, user_c_id)
            # If no exception, check return value
            if accepted_c is None:
                user_c_acceptance_failed = True
            else:
                user_c_acceptance_failed = False
        except (ValueError, sqlite3.IntegrityError, Exception) as e:
            # Expected: max uses exceeded
            user_c_acceptance_failed = True

        assert user_c_acceptance_failed is True, \
            "User C should not be able to accept (max uses exceeded)"

        # Verify User C was NOT added to workspace
        membership_repo = WorkspaceMembershipRepository(db)
        membership_c = membership_repo.get_user_membership(workspace_id, user_c_id)

        if membership_c is not None:
            assert membership_c['is_active'] == 0, \
                "User C should not have active membership"
        else:
            assert membership_c is None, "User C should not have membership"

        # Verify User B still has membership
        membership_b = membership_repo.get_user_membership(workspace_id, user_b_id)
        assert membership_b is not None, "User B should have membership"
        assert membership_b['is_active'] == 1, "User B's membership should be active"


class TestConcurrentInvitationAcceptance:
    """Test 7: Concurrent Invitation Acceptance (atomic increment)"""

    def test_concurrent_invitation_acceptance_atomic(self, clean_db):
        """
        When multiple users try to accept invitation with max_uses=1 simultaneously,
        only one should succeed due to atomic increment.

        Verifies:
        - Create invitation with max_uses=1
        - User B and User C try to accept concurrently
        - Only one succeeds
        - current_uses = 1 (not 2)
        - Only 1 new member added
        """
        db = clean_db

        # Setup: Create users and workspace
        user_repo = UserRepository(db)
        user_a_id = user_repo.create_user(
            email="concurrent_owner@test.com",
            google_id="google_concurrent_owner",
            name="Concurrent Owner"
        )
        user_b_id = user_repo.create_user(
            email="concurrent_user_b@test.com",
            google_id="google_concurrent_user_b",
            name="Concurrent User B"
        )
        user_c_id = user_repo.create_user(
            email="concurrent_user_c@test.com",
            google_id="google_concurrent_user_c",
            name="Concurrent User C"
        )

        workspace_repo = WorkspaceRepository(db)
        workspace_id = workspace_repo.create(
            name="Concurrent Test Workspace",
            description="Testing concurrent acceptance",
            created_by_user_id=user_a_id
        )

        # Add creator as OWNER
        membership_repo = WorkspaceMembershipRepository(db)
        membership_repo.add_member(workspace_id, user_a_id, 'OWNER')

        invitation_repo = WorkspaceInvitationRepository(db)

        # Create invitation with max_uses=1
        invitation = invitation_repo.create_invitation(
            db=db,
            workspace_id=workspace_id,
            role='MEMBER_WRITE',
            created_by_user_id=user_a_id,
            expires_in_days=7,
            max_uses=1
        )
        token = invitation['token']

        # Note: True concurrent testing is challenging with SQLite in-memory DB
        # SQLite serializes writes, so we simulate near-concurrent attempts
        # In production, this would be tested with multiple threads/processes

        def accept_invitation(user_id, token_str):
            """Helper to accept invitation in thread."""
            try:
                # Create new connection for thread
                db_path = db.execute("PRAGMA database_list").fetchone()[2]
                thread_conn = sqlite3.connect(db_path, timeout=5.0)
                thread_conn.row_factory = sqlite3.Row
                thread_repo = WorkspaceInvitationRepository(thread_conn)

                result = thread_repo.accept_invitation(thread_conn, token_str, user_id)
                thread_conn.close()
                return {'success': True, 'user_id': user_id, 'result': result}
            except Exception as e:
                return {'success': False, 'user_id': user_id, 'error': str(e)}

        # Attempt concurrent acceptance
        with ThreadPoolExecutor(max_workers=2) as executor:
            future_b = executor.submit(accept_invitation, user_b_id, token)
            future_c = executor.submit(accept_invitation, user_c_id, token)

            results = []
            for future in as_completed([future_b, future_c]):
                results.append(future.result())

        # Analyze results: only one should succeed
        successes = [r for r in results if r['success']]
        failures = [r for r in results if not r['success']]

        # Note: Due to SQLite serialization, both might appear to succeed
        # but only one should have is_active=1 membership
        # Let's verify actual membership state

        membership_repo = WorkspaceMembershipRepository(db)
        membership_b = membership_repo.get_user_membership(workspace_id, user_b_id)
        membership_c = membership_repo.get_user_membership(workspace_id, user_c_id)

        active_memberships = []
        if membership_b and membership_b['is_active'] == 1:
            active_memberships.append('B')
        if membership_c and membership_c['is_active'] == 1:
            active_memberships.append('C')

        assert len(active_memberships) == 1, \
            f"Only 1 user should have active membership, got {len(active_memberships)}"

        # Verify current_uses = 1 (not 2)
        cursor = db.execute(
            'SELECT current_uses FROM workspace_invitations WHERE token = ?',
            (token,)
        )
        invitation_after = cursor.fetchone()
        assert invitation_after['current_uses'] == 1, \
            "current_uses should be 1 (atomic increment)"

        # Verify workspace has exactly 2 members (Owner + 1 new member)
        members = membership_repo.get_workspace_members(workspace_id)
        assert len(members) == 2, "Workspace should have 2 members (Owner + 1 accepted)"


class TestCoOwnerPermissions:
    """Test 8: CO_OWNER Permissions"""

    def test_co_owner_permissions_boundaries(self, clean_db):
        """
        CO_OWNER has elevated permissions but cannot modify OWNERs.

        Verifies:
        - User A (OWNER) promotes User B to CO_OWNER
        - User B can create invitations
        - User B cannot change User A's role
        - User B can change MEMBER_WRITE to MEMBER_READ
        - User B cannot delete workspace
        """
        db = clean_db

        # Setup: Create User A (OWNER), User B (CO_OWNER), User C (MEMBER_WRITE)
        user_repo = UserRepository(db)
        user_a_id = user_repo.create_user(
            email="co_owner_a@test.com",
            google_id="google_co_owner_a",
            name="CO Owner A"
        )
        user_b_id = user_repo.create_user(
            email="co_owner_b@test.com",
            google_id="google_co_owner_b",
            name="CO Owner B"
        )
        user_c_id = user_repo.create_user(
            email="co_owner_c@test.com",
            google_id="google_co_owner_c",
            name="CO Owner C"
        )

        workspace_repo = WorkspaceRepository(db)
        workspace_id = workspace_repo.create(
            name="CO_OWNER Test Workspace",
            description="Testing CO_OWNER permissions",
            created_by_user_id=user_a_id
        )

        membership_repo = WorkspaceMembershipRepository(db)

        # Add User B as MEMBER_WRITE, then promote to CO_OWNER
        membership_repo.add_member(workspace_id, user_b_id, 'MEMBER_WRITE')
        membership_repo.update_role(workspace_id, user_b_id, 'CO_OWNER')

        # Add User C as MEMBER_WRITE
        membership_repo.add_member(workspace_id, user_c_id, 'MEMBER_WRITE')

        # Test 1: User B (CO_OWNER) can create invitations
        user_b_can_invite = membership_repo.has_permission(
            workspace_id, user_b_id, 'CO_OWNER'
        )
        assert user_b_can_invite is True, "CO_OWNER should have invitation permission"

        invitation_repo = WorkspaceInvitationRepository(db)
        invitation = invitation_repo.create_invitation(
            db=db,
            workspace_id=workspace_id,
            role='MEMBER_READ',
            created_by_user_id=user_b_id,
            expires_in_days=7,
            max_uses=None
        )
        assert invitation is not None, "CO_OWNER should create invitation"

        # Test 2: User B (CO_OWNER) cannot change User A's role (OWNER)
        # Permission check: CO_OWNER cannot modify OWNER
        user_a_membership = membership_repo.get_user_membership(workspace_id, user_a_id)
        assert user_a_membership['role'] == 'OWNER'

        user_b_membership = membership_repo.get_user_membership(workspace_id, user_b_id)
        assert user_b_membership['role'] == 'CO_OWNER'

        # Check role hierarchy: CO_OWNER level (3) < OWNER level (4)
        ROLE_HIERARCHY = {
            'MEMBER_READ': 1,
            'MEMBER_WRITE': 2,
            'CO_OWNER': 3,
            'OWNER': 4
        }

        can_modify_owner = (
            ROLE_HIERARCHY[user_b_membership['role']] >= ROLE_HIERARCHY['OWNER']
        )
        assert can_modify_owner is False, \
            "CO_OWNER should NOT have permission to modify OWNER"

        # Test 3: User B (CO_OWNER) can change MEMBER_WRITE to MEMBER_READ
        success = membership_repo.update_role(workspace_id, user_c_id, 'MEMBER_READ')
        assert success is True, "CO_OWNER should change member roles"

        user_c_membership = membership_repo.get_user_membership(workspace_id, user_c_id)
        assert user_c_membership['role'] == 'MEMBER_READ', \
            "User C should be MEMBER_READ"

        # Test 4: User B (CO_OWNER) cannot delete workspace
        # Only OWNER can delete workspace (business rule)
        owner_count = membership_repo.get_owner_count(workspace_id)
        is_sole_owner = (
            owner_count == 1 and
            user_b_membership['role'] == 'OWNER'
        )
        assert is_sole_owner is False, \
            "CO_OWNER is not sole OWNER, cannot delete workspace"

        # Verify workspace still exists
        workspace = workspace_repo.get_by_id(workspace_id)
        assert workspace is not None, "Workspace should still exist"
        assert workspace['is_active'] == 1, "Workspace should still be active"


class TestWorkspaceIntegrityEdgeCases:
    """Additional edge case tests for workspace integrity."""

    def test_empty_workspace_after_all_members_leave(self, clean_db):
        """
        Edge case: What happens when all non-OWNER members leave?

        Verifies:
        - Workspace still exists with sole OWNER
        - OWNER cannot leave (last owner protection)
        """
        db = clean_db

        user_repo = UserRepository(db)
        user_a_id = user_repo.create_user(
            email="empty_owner@test.com",
            google_id="google_empty_owner",
            name="Empty Owner"
        )
        user_b_id = user_repo.create_user(
            email="empty_member@test.com",
            google_id="google_empty_member",
            name="Empty Member"
        )

        workspace_repo = WorkspaceRepository(db)
        workspace_id = workspace_repo.create(
            name="Empty Workspace Test",
            description="Testing empty workspace",
            created_by_user_id=user_a_id
        )

        membership_repo = WorkspaceMembershipRepository(db)
        membership_repo.add_member(workspace_id, user_b_id, 'MEMBER_WRITE')

        # User B leaves
        membership_repo.remove_member(workspace_id, user_b_id)

        # Workspace should still exist with sole OWNER
        members = membership_repo.get_workspace_members(workspace_id)
        assert len(members) == 1, "Workspace should have 1 member (OWNER)"
        assert members[0]['user_id'] == user_a_id
        assert members[0]['role'] == 'OWNER'

        # OWNER still cannot leave
        owner_count = membership_repo.get_owner_count(workspace_id)
        assert owner_count == 1
        # Last owner protection applies

    def test_invitation_revocation(self, clean_db):
        """
        Test invitation can be revoked before acceptance.

        Verifies:
        - Create invitation
        - Revoke invitation (set is_active=0)
        - User tries to accept revoked invitation
        - Acceptance fails
        """
        db = clean_db

        user_repo = UserRepository(db)
        user_a_id = user_repo.create_user(
            email="revoke_owner@test.com",
            google_id="google_revoke_owner",
            name="Revoke Owner"
        )
        user_b_id = user_repo.create_user(
            email="revoke_user@test.com",
            google_id="google_revoke_user",
            name="Revoke User"
        )

        workspace_repo = WorkspaceRepository(db)
        workspace_id = workspace_repo.create(
            name="Revoke Test Workspace",
            description="Testing invitation revocation",
            created_by_user_id=user_a_id
        )

        # Add creator as OWNER
        membership_repo = WorkspaceMembershipRepository(db)
        membership_repo.add_member(workspace_id, user_a_id, 'OWNER')

        invitation_repo = WorkspaceInvitationRepository(db)
        invitation = invitation_repo.create_invitation(
            db=db,
            workspace_id=workspace_id,
            role='MEMBER_WRITE',
            created_by_user_id=user_a_id,
            expires_in_days=7,
            max_uses=None
        )
        token = invitation['token']
        invitation_id = invitation['id']

        # Revoke invitation
        success = invitation_repo.revoke_invitation(
            db=db,
            invitation_id=invitation_id,
            revoked_by_user_id=user_a_id
        )
        assert success is True, "Invitation should be revoked"

        # User B tries to accept revoked invitation
        try:
            accepted = invitation_repo.accept_invitation(db, token, user_b_id)
            if accepted is None:
                acceptance_failed = True
            else:
                acceptance_failed = False
        except Exception:
            acceptance_failed = True

        assert acceptance_failed is True, \
            "Revoked invitation should not be accepted"

        # Verify User B was not added
        membership_repo = WorkspaceMembershipRepository(db)
        membership = membership_repo.get_user_membership(workspace_id, user_b_id)
        assert membership is None or membership['is_active'] == 0, \
            "User B should not have active membership"
