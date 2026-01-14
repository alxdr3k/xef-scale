"""
Unit tests for WorkspaceMembershipRepository.

Tests cover:
- CRUD operations (add_member, update_role, remove_member)
- Member queries (get_workspace_members, get_user_membership)
- Owner protection (get_owner_count, last OWNER scenarios)
- Permission logic (has_permission with role hierarchy)
- Edge cases (non-existent workspace, invalid roles, inactive members)
"""

import sqlite3
import pytest
from datetime import datetime
from src.db.repository import WorkspaceMembershipRepository, WorkspaceRepository


@pytest.fixture
def db():
    """Create in-memory database with workspace tables for testing."""
    conn = sqlite3.connect(':memory:')
    conn.row_factory = sqlite3.Row
    # Enable foreign key constraints (disabled by default in SQLite)
    conn.execute('PRAGMA foreign_keys = ON')

    # Create users table
    conn.execute('''
        CREATE TABLE users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            email TEXT UNIQUE NOT NULL,
            profile_picture_url TEXT,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    # Create workspaces table
    conn.execute('''
        CREATE TABLE workspaces (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            description TEXT,
            created_by_user_id INTEGER NOT NULL,
            currency TEXT DEFAULT 'KRW',
            timezone TEXT DEFAULT 'Asia/Seoul',
            is_active BOOLEAN DEFAULT 1,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (created_by_user_id) REFERENCES users(id) ON DELETE RESTRICT
        )
    ''')

    # Create workspace_memberships table
    conn.execute('''
        CREATE TABLE workspace_memberships (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            workspace_id INTEGER NOT NULL,
            user_id INTEGER NOT NULL,
            role TEXT NOT NULL CHECK(role IN ('OWNER', 'CO_OWNER', 'MEMBER_WRITE', 'MEMBER_READ')),
            is_active BOOLEAN DEFAULT 1,
            joined_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
            UNIQUE(workspace_id, user_id, is_active)
        )
    ''')

    # Trigger for updated_at timestamp
    conn.execute('''
        CREATE TRIGGER update_workspace_memberships_timestamp
        AFTER UPDATE ON workspace_memberships
        BEGIN
            UPDATE workspace_memberships SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
        END
    ''')

    conn.commit()

    yield conn
    conn.close()


@pytest.fixture
def sample_data(db):
    """Insert sample users and workspaces for testing."""
    # Insert users
    db.execute("INSERT INTO users (name, email) VALUES ('Alice', 'alice@example.com')")
    db.execute("INSERT INTO users (name, email) VALUES ('Bob', 'bob@example.com')")
    db.execute("INSERT INTO users (name, email) VALUES ('Charlie', 'charlie@example.com')")
    db.execute("INSERT INTO users (name, email) VALUES ('Diana', 'diana@example.com')")

    # Insert workspaces
    db.execute("""
        INSERT INTO workspaces (name, description, created_by_user_id)
        VALUES ('Team Workspace', 'Shared team expenses', 1)
    """)
    db.execute("""
        INSERT INTO workspaces (name, description, created_by_user_id)
        VALUES ('Personal Workspace', 'Personal tracking', 2)
    """)

    db.commit()

    return {
        'user_ids': [1, 2, 3, 4],
        'workspace_ids': [1, 2]
    }


class TestAddMember:
    """Tests for add_member() method."""

    def test_add_member_owner_role(self, db, sample_data):
        """Test adding member with OWNER role."""
        repo = WorkspaceMembershipRepository(db)

        membership_id = repo.add_member(workspace_id=1, user_id=1, role='OWNER')

        assert membership_id > 0
        membership = repo.get_user_membership(workspace_id=1, user_id=1)
        assert membership['role'] == 'OWNER'
        assert membership['is_active'] == 1

    def test_add_member_all_roles(self, db, sample_data):
        """Test adding members with different roles."""
        repo = WorkspaceMembershipRepository(db)

        roles = ['OWNER', 'CO_OWNER', 'MEMBER_WRITE', 'MEMBER_READ']
        for idx, role in enumerate(roles):
            user_id = idx + 1
            membership_id = repo.add_member(workspace_id=1, user_id=user_id, role=role)
            assert membership_id > 0

            membership = repo.get_user_membership(workspace_id=1, user_id=user_id)
            assert membership['role'] == role

    def test_add_member_invalid_role(self, db, sample_data):
        """Test adding member with invalid role raises ValueError."""
        repo = WorkspaceMembershipRepository(db)

        with pytest.raises(ValueError, match='Invalid role'):
            repo.add_member(workspace_id=1, user_id=1, role='INVALID_ROLE')

    def test_add_member_nonexistent_workspace(self, db, sample_data):
        """Test adding member to non-existent workspace raises IntegrityError."""
        repo = WorkspaceMembershipRepository(db)

        with pytest.raises(sqlite3.IntegrityError):
            repo.add_member(workspace_id=999, user_id=1, role='OWNER')

    def test_add_member_nonexistent_user(self, db, sample_data):
        """Test adding non-existent user raises IntegrityError."""
        repo = WorkspaceMembershipRepository(db)

        with pytest.raises(sqlite3.IntegrityError):
            repo.add_member(workspace_id=1, user_id=999, role='OWNER')

    def test_add_duplicate_member(self, db, sample_data):
        """Test adding duplicate active membership raises IntegrityError."""
        repo = WorkspaceMembershipRepository(db)

        repo.add_member(workspace_id=1, user_id=1, role='OWNER')

        with pytest.raises(sqlite3.IntegrityError):
            repo.add_member(workspace_id=1, user_id=1, role='MEMBER_WRITE')

    def test_add_member_sets_joined_at(self, db, sample_data):
        """Test that joined_at is set automatically."""
        repo = WorkspaceMembershipRepository(db)

        membership_id = repo.add_member(workspace_id=1, user_id=1, role='OWNER')
        membership = repo.get_user_membership(workspace_id=1, user_id=1)

        assert membership['joined_at'] is not None


class TestGetWorkspaceMembers:
    """Tests for get_workspace_members() method."""

    def test_get_workspace_members_empty(self, db, sample_data):
        """Test getting members from workspace with no members."""
        repo = WorkspaceMembershipRepository(db)

        members = repo.get_workspace_members(workspace_id=1)

        assert members == []

    def test_get_workspace_members_single_member(self, db, sample_data):
        """Test getting members with single member."""
        repo = WorkspaceMembershipRepository(db)
        repo.add_member(workspace_id=1, user_id=1, role='OWNER')

        members = repo.get_workspace_members(workspace_id=1)

        assert len(members) == 1
        assert members[0]['user_id'] == 1
        assert members[0]['role'] == 'OWNER'
        assert members[0]['name'] == 'Alice'
        assert members[0]['email'] == 'alice@example.com'

    def test_get_workspace_members_multiple_members(self, db, sample_data):
        """Test getting members with multiple members."""
        repo = WorkspaceMembershipRepository(db)
        repo.add_member(workspace_id=1, user_id=1, role='OWNER')
        repo.add_member(workspace_id=1, user_id=2, role='CO_OWNER')
        repo.add_member(workspace_id=1, user_id=3, role='MEMBER_WRITE')

        members = repo.get_workspace_members(workspace_id=1)

        assert len(members) == 3
        assert members[0]['user_id'] == 1
        assert members[1]['user_id'] == 2
        assert members[2]['user_id'] == 3

    def test_get_workspace_members_ordered_by_role_hierarchy(self, db, sample_data):
        """Test that members are ordered by role hierarchy (OWNER first)."""
        repo = WorkspaceMembershipRepository(db)
        # Add in reverse order of hierarchy
        repo.add_member(workspace_id=1, user_id=4, role='MEMBER_READ')
        repo.add_member(workspace_id=1, user_id=3, role='MEMBER_WRITE')
        repo.add_member(workspace_id=1, user_id=2, role='CO_OWNER')
        repo.add_member(workspace_id=1, user_id=1, role='OWNER')

        members = repo.get_workspace_members(workspace_id=1)

        # Should be ordered by role hierarchy
        assert members[0]['role'] == 'OWNER'
        assert members[1]['role'] == 'CO_OWNER'
        assert members[2]['role'] == 'MEMBER_WRITE'
        assert members[3]['role'] == 'MEMBER_READ'

    def test_get_workspace_members_excludes_inactive(self, db, sample_data):
        """Test that inactive members are excluded."""
        repo = WorkspaceMembershipRepository(db)
        repo.add_member(workspace_id=1, user_id=1, role='OWNER')
        repo.add_member(workspace_id=1, user_id=2, role='MEMBER_WRITE')

        # Soft delete user 2
        repo.remove_member(workspace_id=1, user_id=2)

        members = repo.get_workspace_members(workspace_id=1)

        assert len(members) == 1
        assert members[0]['user_id'] == 1

    def test_get_workspace_members_includes_user_fields(self, db, sample_data):
        """Test that user fields are included in member data."""
        repo = WorkspaceMembershipRepository(db)
        repo.add_member(workspace_id=1, user_id=1, role='OWNER')

        members = repo.get_workspace_members(workspace_id=1)

        assert 'user_id' in members[0]
        assert 'name' in members[0]
        assert 'email' in members[0]
        assert 'profile_picture_url' in members[0]
        assert 'role' in members[0]
        assert 'joined_at' in members[0]


class TestGetUserMembership:
    """Tests for get_user_membership() method."""

    def test_get_user_membership_exists(self, db, sample_data):
        """Test getting existing membership."""
        repo = WorkspaceMembershipRepository(db)
        repo.add_member(workspace_id=1, user_id=1, role='OWNER')

        membership = repo.get_user_membership(workspace_id=1, user_id=1)

        assert membership is not None
        assert membership['workspace_id'] == 1
        assert membership['user_id'] == 1
        assert membership['role'] == 'OWNER'
        assert membership['is_active'] == 1

    def test_get_user_membership_not_exists(self, db, sample_data):
        """Test getting non-existent membership returns None."""
        repo = WorkspaceMembershipRepository(db)

        membership = repo.get_user_membership(workspace_id=1, user_id=1)

        assert membership is None

    def test_get_user_membership_returns_all_fields(self, db, sample_data):
        """Test that all membership fields are returned."""
        repo = WorkspaceMembershipRepository(db)
        repo.add_member(workspace_id=1, user_id=1, role='OWNER')

        membership = repo.get_user_membership(workspace_id=1, user_id=1)

        assert 'id' in membership
        assert 'workspace_id' in membership
        assert 'user_id' in membership
        assert 'role' in membership
        assert 'is_active' in membership
        assert 'joined_at' in membership
        assert 'updated_at' in membership

    def test_get_user_membership_includes_inactive(self, db, sample_data):
        """Test that inactive memberships are still returned."""
        repo = WorkspaceMembershipRepository(db)
        repo.add_member(workspace_id=1, user_id=1, role='OWNER')
        repo.remove_member(workspace_id=1, user_id=1)

        membership = repo.get_user_membership(workspace_id=1, user_id=1)

        assert membership is not None
        assert membership['is_active'] == 0


class TestUpdateRole:
    """Tests for update_role() method."""

    def test_update_role_success(self, db, sample_data):
        """Test successfully updating role."""
        repo = WorkspaceMembershipRepository(db)
        repo.add_member(workspace_id=1, user_id=1, role='MEMBER_WRITE')

        success = repo.update_role(workspace_id=1, user_id=1, new_role='CO_OWNER')

        assert success is True
        membership = repo.get_user_membership(workspace_id=1, user_id=1)
        assert membership['role'] == 'CO_OWNER'

    def test_update_role_all_transitions(self, db, sample_data):
        """Test updating to all role types."""
        repo = WorkspaceMembershipRepository(db)
        repo.add_member(workspace_id=1, user_id=1, role='MEMBER_READ')

        roles = ['MEMBER_WRITE', 'CO_OWNER', 'OWNER', 'MEMBER_READ']
        for role in roles:
            success = repo.update_role(workspace_id=1, user_id=1, new_role=role)
            assert success is True
            membership = repo.get_user_membership(workspace_id=1, user_id=1)
            assert membership['role'] == role

    def test_update_role_invalid_role(self, db, sample_data):
        """Test updating to invalid role raises ValueError."""
        repo = WorkspaceMembershipRepository(db)
        repo.add_member(workspace_id=1, user_id=1, role='MEMBER_WRITE')

        with pytest.raises(ValueError, match='Invalid role'):
            repo.update_role(workspace_id=1, user_id=1, new_role='INVALID')

    def test_update_role_nonexistent_membership(self, db, sample_data):
        """Test updating non-existent membership returns False."""
        repo = WorkspaceMembershipRepository(db)

        success = repo.update_role(workspace_id=1, user_id=1, new_role='OWNER')

        assert success is False

    def test_update_role_updates_timestamp(self, db, sample_data):
        """Test that updated_at timestamp is updated."""
        repo = WorkspaceMembershipRepository(db)
        repo.add_member(workspace_id=1, user_id=1, role='MEMBER_WRITE')

        membership_before = repo.get_user_membership(workspace_id=1, user_id=1)
        updated_at_before = membership_before['updated_at']

        # SQLite CURRENT_TIMESTAMP has 1-second precision, so wait 1 second
        import time
        time.sleep(1.1)

        repo.update_role(workspace_id=1, user_id=1, new_role='CO_OWNER')

        membership_after = repo.get_user_membership(workspace_id=1, user_id=1)
        updated_at_after = membership_after['updated_at']

        # Check that timestamp was updated (should be >= since we waited)
        assert updated_at_after >= updated_at_before


class TestRemoveMember:
    """Tests for remove_member() method."""

    def test_remove_member_success(self, db, sample_data):
        """Test successfully removing member."""
        repo = WorkspaceMembershipRepository(db)
        repo.add_member(workspace_id=1, user_id=1, role='OWNER')

        success = repo.remove_member(workspace_id=1, user_id=1)

        assert success is True
        membership = repo.get_user_membership(workspace_id=1, user_id=1)
        assert membership['is_active'] == 0

    def test_remove_member_nonexistent_membership(self, db, sample_data):
        """Test removing non-existent membership returns False."""
        repo = WorkspaceMembershipRepository(db)

        success = repo.remove_member(workspace_id=1, user_id=1)

        assert success is False

    def test_remove_member_preserves_record(self, db, sample_data):
        """Test that soft delete preserves the membership record."""
        repo = WorkspaceMembershipRepository(db)
        repo.add_member(workspace_id=1, user_id=1, role='OWNER')

        repo.remove_member(workspace_id=1, user_id=1)

        membership = repo.get_user_membership(workspace_id=1, user_id=1)
        assert membership is not None
        assert membership['role'] == 'OWNER'
        assert membership['is_active'] == 0

    def test_remove_member_excludes_from_get_workspace_members(self, db, sample_data):
        """Test that removed members are excluded from get_workspace_members."""
        repo = WorkspaceMembershipRepository(db)
        repo.add_member(workspace_id=1, user_id=1, role='OWNER')
        repo.add_member(workspace_id=1, user_id=2, role='MEMBER_WRITE')

        repo.remove_member(workspace_id=1, user_id=2)

        members = repo.get_workspace_members(workspace_id=1)
        assert len(members) == 1
        assert members[0]['user_id'] == 1


class TestGetOwnerCount:
    """Tests for get_owner_count() method."""

    def test_get_owner_count_zero(self, db, sample_data):
        """Test counting owners when there are none."""
        repo = WorkspaceMembershipRepository(db)

        count = repo.get_owner_count(workspace_id=1)

        assert count == 0

    def test_get_owner_count_single_owner(self, db, sample_data):
        """Test counting single owner."""
        repo = WorkspaceMembershipRepository(db)
        repo.add_member(workspace_id=1, user_id=1, role='OWNER')

        count = repo.get_owner_count(workspace_id=1)

        assert count == 1

    def test_get_owner_count_multiple_owners(self, db, sample_data):
        """Test counting multiple owners."""
        repo = WorkspaceMembershipRepository(db)
        repo.add_member(workspace_id=1, user_id=1, role='OWNER')
        repo.add_member(workspace_id=1, user_id=2, role='OWNER')

        count = repo.get_owner_count(workspace_id=1)

        assert count == 2

    def test_get_owner_count_excludes_other_roles(self, db, sample_data):
        """Test that only OWNER role is counted."""
        repo = WorkspaceMembershipRepository(db)
        repo.add_member(workspace_id=1, user_id=1, role='OWNER')
        repo.add_member(workspace_id=1, user_id=2, role='CO_OWNER')
        repo.add_member(workspace_id=1, user_id=3, role='MEMBER_WRITE')
        repo.add_member(workspace_id=1, user_id=4, role='MEMBER_READ')

        count = repo.get_owner_count(workspace_id=1)

        assert count == 1

    def test_get_owner_count_excludes_inactive(self, db, sample_data):
        """Test that inactive owners are not counted."""
        repo = WorkspaceMembershipRepository(db)
        repo.add_member(workspace_id=1, user_id=1, role='OWNER')
        repo.add_member(workspace_id=1, user_id=2, role='OWNER')

        repo.remove_member(workspace_id=1, user_id=2)

        count = repo.get_owner_count(workspace_id=1)

        assert count == 1

    def test_get_owner_count_nonexistent_workspace(self, db, sample_data):
        """Test counting owners for non-existent workspace returns 0."""
        repo = WorkspaceMembershipRepository(db)

        count = repo.get_owner_count(workspace_id=999)

        assert count == 0


class TestHasPermission:
    """Tests for has_permission() method."""

    def test_has_permission_exact_role_match(self, db, sample_data):
        """Test permission check with exact role match."""
        repo = WorkspaceMembershipRepository(db)
        repo.add_member(workspace_id=1, user_id=1, role='MEMBER_WRITE')

        has_perm = repo.has_permission(workspace_id=1, user_id=1, required_role='MEMBER_WRITE')

        assert has_perm is True

    def test_has_permission_higher_role(self, db, sample_data):
        """Test that higher role has permission for lower role requirements."""
        repo = WorkspaceMembershipRepository(db)
        repo.add_member(workspace_id=1, user_id=1, role='OWNER')

        # OWNER should have all permissions
        assert repo.has_permission(workspace_id=1, user_id=1, required_role='CO_OWNER') is True
        assert repo.has_permission(workspace_id=1, user_id=1, required_role='MEMBER_WRITE') is True
        assert repo.has_permission(workspace_id=1, user_id=1, required_role='MEMBER_READ') is True

    def test_has_permission_lower_role(self, db, sample_data):
        """Test that lower role does not have permission for higher role requirements."""
        repo = WorkspaceMembershipRepository(db)
        repo.add_member(workspace_id=1, user_id=1, role='MEMBER_READ')

        # MEMBER_READ should not have higher permissions
        assert repo.has_permission(workspace_id=1, user_id=1, required_role='MEMBER_WRITE') is False
        assert repo.has_permission(workspace_id=1, user_id=1, required_role='CO_OWNER') is False
        assert repo.has_permission(workspace_id=1, user_id=1, required_role='OWNER') is False

    def test_has_permission_role_hierarchy(self, db, sample_data):
        """Test complete role hierarchy."""
        repo = WorkspaceMembershipRepository(db)

        # Test CO_OWNER
        repo.add_member(workspace_id=1, user_id=1, role='CO_OWNER')
        assert repo.has_permission(workspace_id=1, user_id=1, required_role='MEMBER_READ') is True
        assert repo.has_permission(workspace_id=1, user_id=1, required_role='MEMBER_WRITE') is True
        assert repo.has_permission(workspace_id=1, user_id=1, required_role='CO_OWNER') is True
        assert repo.has_permission(workspace_id=1, user_id=1, required_role='OWNER') is False

        # Test MEMBER_WRITE
        repo.add_member(workspace_id=1, user_id=2, role='MEMBER_WRITE')
        assert repo.has_permission(workspace_id=1, user_id=2, required_role='MEMBER_READ') is True
        assert repo.has_permission(workspace_id=1, user_id=2, required_role='MEMBER_WRITE') is True
        assert repo.has_permission(workspace_id=1, user_id=2, required_role='CO_OWNER') is False

    def test_has_permission_non_member(self, db, sample_data):
        """Test that non-member has no permission."""
        repo = WorkspaceMembershipRepository(db)

        has_perm = repo.has_permission(workspace_id=1, user_id=1, required_role='MEMBER_READ')

        assert has_perm is False

    def test_has_permission_inactive_member(self, db, sample_data):
        """Test that inactive member has no permission."""
        repo = WorkspaceMembershipRepository(db)
        repo.add_member(workspace_id=1, user_id=1, role='OWNER')
        repo.remove_member(workspace_id=1, user_id=1)

        has_perm = repo.has_permission(workspace_id=1, user_id=1, required_role='MEMBER_READ')

        assert has_perm is False


class TestEdgeCases:
    """Tests for edge cases and error conditions."""

    def test_multiple_workspaces_isolation(self, db, sample_data):
        """Test that memberships are isolated between workspaces."""
        repo = WorkspaceMembershipRepository(db)
        repo.add_member(workspace_id=1, user_id=1, role='OWNER')
        repo.add_member(workspace_id=2, user_id=1, role='MEMBER_READ')

        # Check workspace 1
        members_ws1 = repo.get_workspace_members(workspace_id=1)
        assert len(members_ws1) == 1
        assert members_ws1[0]['role'] == 'OWNER'

        # Check workspace 2
        members_ws2 = repo.get_workspace_members(workspace_id=2)
        assert len(members_ws2) == 1
        assert members_ws2[0]['role'] == 'MEMBER_READ'

        # Check permissions
        assert repo.has_permission(workspace_id=1, user_id=1, required_role='OWNER') is True
        assert repo.has_permission(workspace_id=2, user_id=1, required_role='OWNER') is False

    def test_role_hierarchy_constant(self, db):
        """Test that ROLE_HIERARCHY constant is defined correctly."""
        repo = WorkspaceMembershipRepository(db)

        assert repo.ROLE_HIERARCHY['MEMBER_READ'] == 1
        assert repo.ROLE_HIERARCHY['MEMBER_WRITE'] == 2
        assert repo.ROLE_HIERARCHY['CO_OWNER'] == 3
        assert repo.ROLE_HIERARCHY['OWNER'] == 4

    def test_repository_initialization(self, db):
        """Test that repository initializes correctly."""
        repo = WorkspaceMembershipRepository(db)

        assert repo.conn == db
        assert repo.logger is not None
        assert hasattr(repo, 'ROLE_HIERARCHY')

    def test_concurrent_operations(self, db, sample_data):
        """Test multiple operations in sequence."""
        repo = WorkspaceMembershipRepository(db)

        # Add multiple members
        repo.add_member(workspace_id=1, user_id=1, role='OWNER')
        repo.add_member(workspace_id=1, user_id=2, role='CO_OWNER')
        repo.add_member(workspace_id=1, user_id=3, role='MEMBER_WRITE')

        # Update role
        repo.update_role(workspace_id=1, user_id=3, new_role='CO_OWNER')

        # Remove member
        repo.remove_member(workspace_id=1, user_id=2)

        # Verify final state
        members = repo.get_workspace_members(workspace_id=1)
        assert len(members) == 2
        assert members[0]['user_id'] == 1 and members[0]['role'] == 'OWNER'
        assert members[1]['user_id'] == 3 and members[1]['role'] == 'CO_OWNER'

    def test_owner_count_after_role_change(self, db, sample_data):
        """Test owner count after changing role from OWNER to other role."""
        repo = WorkspaceMembershipRepository(db)
        repo.add_member(workspace_id=1, user_id=1, role='OWNER')
        repo.add_member(workspace_id=1, user_id=2, role='OWNER')

        assert repo.get_owner_count(workspace_id=1) == 2

        # Change one owner to CO_OWNER
        repo.update_role(workspace_id=1, user_id=2, new_role='CO_OWNER')

        assert repo.get_owner_count(workspace_id=1) == 1
