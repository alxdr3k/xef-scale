"""
Unit tests for WorkspaceRepository.
Tests workspace management including CRUD operations, membership queries, and member counting.
"""

import sqlite3
import pytest
from datetime import datetime
from src.db.connection import DatabaseConnection
from src.db.repository import WorkspaceRepository, UserRepository


@pytest.fixture
def workspace_repo(test_db_override):
    """Fixture providing WorkspaceRepository with test database connection."""
    conn = DatabaseConnection.get_instance()
    repo = WorkspaceRepository(conn)

    # Clean up test workspaces before each test
    conn.execute("DELETE FROM workspaces WHERE name LIKE 'Test Workspace%'")
    conn.commit()

    yield repo

    # Clean up after test
    conn.execute("DELETE FROM workspaces WHERE name LIKE 'Test Workspace%'")
    conn.commit()


@pytest.fixture
def test_users(test_db_override):
    """Fixture providing test users for workspace tests."""
    conn = DatabaseConnection.get_instance()
    user_repo = UserRepository(conn)

    # Create test users
    user1_id = user_repo.create_user(
        email='workspace_user1@test.example.com',
        google_id='google_workspace_1',
        name='Workspace User 1'
    )
    user2_id = user_repo.create_user(
        email='workspace_user2@test.example.com',
        google_id='google_workspace_2',
        name='Workspace User 2'
    )

    yield {'user1_id': user1_id, 'user2_id': user2_id}

    # Clean up test users
    # First delete related workspaces and memberships to avoid foreign key constraints
    try:
        # Delete workspaces created by test users
        conn.execute("DELETE FROM workspaces WHERE created_by_user_id IN (?, ?)",
                    (user1_id, user2_id))
        # Delete workspace memberships
        conn.execute("DELETE FROM workspace_memberships WHERE user_id IN (?, ?)",
                    (user1_id, user2_id))
        # Now delete test users
        conn.execute("DELETE FROM users WHERE email LIKE '%workspace_user%@test.example.com'")
        conn.commit()
    except Exception as e:
        # If cleanup fails, rollback to prevent test database corruption
        conn.rollback()
        print(f"Warning: Test user cleanup failed: {e}")


def test_create_workspace(workspace_repo, test_users):
    """Test creating a new workspace."""
    workspace_id = workspace_repo.create(
        name='Test Workspace 1',
        description='A test workspace for unit testing',
        created_by_user_id=test_users['user1_id']
    )

    assert workspace_id > 0

    # Verify workspace was created
    workspace = workspace_repo.get_by_id(workspace_id)
    assert workspace is not None
    assert workspace['name'] == 'Test Workspace 1'
    assert workspace['description'] == 'A test workspace for unit testing'
    assert workspace['created_by_user_id'] == test_users['user1_id']
    assert workspace['currency'] == 'KRW'
    assert workspace['timezone'] == 'Asia/Seoul'
    assert workspace['is_active'] == 1
    assert workspace['created_at'] is not None
    assert workspace['updated_at'] is not None


def test_create_workspace_invalid_user(workspace_repo):
    """Test that creating workspace with invalid user ID raises IntegrityError."""
    with pytest.raises(sqlite3.IntegrityError):
        workspace_repo.create(
            name='Test Workspace Invalid',
            description='Should fail',
            created_by_user_id=99999  # Non-existent user
        )


def test_get_by_id(workspace_repo, test_users):
    """Test retrieving workspace by ID."""
    workspace_id = workspace_repo.create(
        name='Test Workspace Get',
        description='Test get by ID',
        created_by_user_id=test_users['user1_id']
    )

    workspace = workspace_repo.get_by_id(workspace_id)
    assert workspace is not None
    assert workspace['id'] == workspace_id
    assert workspace['name'] == 'Test Workspace Get'

    # Non-existent workspace should return None
    workspace = workspace_repo.get_by_id(99999)
    assert workspace is None


def test_get_user_workspaces(workspace_repo, test_users, test_db_override):
    """Test retrieving all workspaces for a user."""
    conn = DatabaseConnection.get_instance()

    # Create workspace
    workspace_id = workspace_repo.create(
        name='Test Workspace User',
        description='Test user workspaces',
        created_by_user_id=test_users['user1_id']
    )

    # Add user as member
    conn.execute('''
        INSERT INTO workspace_memberships (workspace_id, user_id, role)
        VALUES (?, ?, 'OWNER')
    ''', (workspace_id, test_users['user1_id']))
    conn.commit()

    # Add second member
    conn.execute('''
        INSERT INTO workspace_memberships (workspace_id, user_id, role)
        VALUES (?, ?, 'MEMBER_WRITE')
    ''', (workspace_id, test_users['user2_id']))
    conn.commit()

    # Get user workspaces
    workspaces = workspace_repo.get_user_workspaces(test_users['user1_id'])

    # Should return at least one workspace (may include default workspace from migration)
    assert len(workspaces) >= 1

    # Find our test workspace
    test_workspace = next(
        (ws for ws in workspaces if ws['name'] == 'Test Workspace User'),
        None
    )
    assert test_workspace is not None
    assert test_workspace['user_role'] == 'OWNER'
    assert test_workspace['member_count'] == 2  # Both users are members


def test_get_user_workspaces_empty(workspace_repo, test_users, test_db_override):
    """Test retrieving workspaces for user with no workspaces."""
    conn = DatabaseConnection.get_instance()

    # Create a new user without any workspace memberships
    user_repo = UserRepository(conn)
    new_user_id = user_repo.create_user(
        email='no_workspace@test.example.com',
        google_id='google_no_workspace',
        name='No Workspace User'
    )

    # Delete any default workspace memberships that might have been created
    conn.execute('DELETE FROM workspace_memberships WHERE user_id = ?', (new_user_id,))
    conn.commit()

    workspaces = workspace_repo.get_user_workspaces(new_user_id)
    assert workspaces == []

    # Clean up
    conn.execute('DELETE FROM users WHERE id = ?', (new_user_id,))
    conn.commit()


def test_get_user_workspaces_ordering(workspace_repo, test_users, test_db_override):
    """Test that user workspaces are ordered by created_at DESC."""
    import time
    conn = DatabaseConnection.get_instance()

    # Create multiple workspaces with explicit time delay
    workspace1_id = workspace_repo.create(
        name='Test Workspace First',
        description='Created first',
        created_by_user_id=test_users['user1_id']
    )

    # Add delay to ensure different timestamps (SQLite CURRENT_TIMESTAMP has second precision)
    time.sleep(1.1)

    workspace2_id = workspace_repo.create(
        name='Test Workspace Second',
        description='Created second',
        created_by_user_id=test_users['user1_id']
    )

    # Add memberships
    conn.execute('''
        INSERT INTO workspace_memberships (workspace_id, user_id, role)
        VALUES (?, ?, 'OWNER')
    ''', (workspace1_id, test_users['user1_id']))

    conn.execute('''
        INSERT INTO workspace_memberships (workspace_id, user_id, role)
        VALUES (?, ?, 'OWNER')
    ''', (workspace2_id, test_users['user1_id']))
    conn.commit()

    # Get user workspaces
    workspaces = workspace_repo.get_user_workspaces(test_users['user1_id'])

    # Find our test workspaces
    test_workspaces = [
        ws for ws in workspaces
        if ws['name'] in ('Test Workspace First', 'Test Workspace Second')
    ]

    # Should be ordered by created_at DESC (newest first)
    assert len(test_workspaces) >= 2
    # Verify order by comparing IDs since timestamps might be very close
    workspace_names = [ws['name'] for ws in test_workspaces]
    # Second workspace should come before first (DESC order)
    second_idx = workspace_names.index('Test Workspace Second')
    first_idx = workspace_names.index('Test Workspace First')
    assert second_idx < first_idx, "Workspaces should be ordered by created_at DESC"


def test_update_workspace(workspace_repo, test_users):
    """Test updating workspace fields."""
    workspace_id = workspace_repo.create(
        name='Test Workspace Old Name',
        description='Old description',
        created_by_user_id=test_users['user1_id']
    )

    # Update workspace
    success = workspace_repo.update(
        workspace_id=workspace_id,
        updates={
            'name': 'Test Workspace New Name',
            'description': 'New description'
        }
    )

    assert success is True

    # Verify update
    workspace = workspace_repo.get_by_id(workspace_id)
    assert workspace['name'] == 'Test Workspace New Name'
    assert workspace['description'] == 'New description'


def test_update_workspace_partial(workspace_repo, test_users):
    """Test updating only some workspace fields."""
    workspace_id = workspace_repo.create(
        name='Test Workspace Partial',
        description='Original description',
        created_by_user_id=test_users['user1_id']
    )

    # Update only name
    success = workspace_repo.update(
        workspace_id=workspace_id,
        updates={'name': 'Test Workspace Updated'}
    )

    assert success is True

    workspace = workspace_repo.get_by_id(workspace_id)
    assert workspace['name'] == 'Test Workspace Updated'
    assert workspace['description'] == 'Original description'  # Unchanged


def test_update_workspace_invalid_fields(workspace_repo, test_users):
    """Test that updating disallowed fields is ignored."""
    workspace_id = workspace_repo.create(
        name='Test Workspace Invalid Update',
        description='Test description',
        created_by_user_id=test_users['user1_id']
    )

    original_workspace = workspace_repo.get_by_id(workspace_id)

    # Attempt to update disallowed fields
    success = workspace_repo.update(
        workspace_id=workspace_id,
        updates={
            'created_by_user_id': test_users['user2_id'],  # Not allowed
            'currency': 'USD',  # Not allowed
            'timezone': 'UTC'  # Not allowed
        }
    )

    # Should return False because no valid fields to update
    assert success is False

    # Verify fields remain unchanged
    workspace = workspace_repo.get_by_id(workspace_id)
    assert workspace['created_by_user_id'] == original_workspace['created_by_user_id']
    assert workspace['currency'] == original_workspace['currency']
    assert workspace['timezone'] == original_workspace['timezone']


def test_update_workspace_not_found(workspace_repo):
    """Test updating non-existent workspace returns False."""
    success = workspace_repo.update(
        workspace_id=99999,
        updates={'name': 'Should not work'}
    )

    assert success is False


def test_update_workspace_empty_updates(workspace_repo, test_users):
    """Test updating with empty updates dict."""
    workspace_id = workspace_repo.create(
        name='Test Workspace Empty',
        description='Test empty updates',
        created_by_user_id=test_users['user1_id']
    )

    success = workspace_repo.update(
        workspace_id=workspace_id,
        updates={}
    )

    assert success is False


def test_delete_workspace(workspace_repo, test_users):
    """Test soft deleting workspace."""
    workspace_id = workspace_repo.create(
        name='Test Workspace Delete',
        description='To be deleted',
        created_by_user_id=test_users['user1_id']
    )

    # Verify workspace exists and is active
    workspace = workspace_repo.get_by_id(workspace_id)
    assert workspace['is_active'] == 1

    # Delete workspace
    success = workspace_repo.delete(workspace_id)
    assert success is True

    # Verify workspace is soft deleted
    workspace = workspace_repo.get_by_id(workspace_id)
    assert workspace is not None  # Still exists in database
    assert workspace['is_active'] == 0  # But marked as inactive


def test_delete_workspace_not_found(workspace_repo):
    """Test deleting non-existent workspace returns False."""
    success = workspace_repo.delete(99999)
    assert success is False


def test_get_member_count(workspace_repo, test_users, test_db_override):
    """Test counting active members in workspace."""
    conn = DatabaseConnection.get_instance()

    # Create workspace
    workspace_id = workspace_repo.create(
        name='Test Workspace Count',
        description='Test member count',
        created_by_user_id=test_users['user1_id']
    )

    # Add members
    conn.execute('''
        INSERT INTO workspace_memberships (workspace_id, user_id, role)
        VALUES (?, ?, 'OWNER')
    ''', (workspace_id, test_users['user1_id']))

    conn.execute('''
        INSERT INTO workspace_memberships (workspace_id, user_id, role)
        VALUES (?, ?, 'MEMBER_WRITE')
    ''', (workspace_id, test_users['user2_id']))
    conn.commit()

    # Count members
    count = workspace_repo.get_member_count(workspace_id)
    assert count == 2


def test_get_member_count_with_inactive_members(workspace_repo, test_users, test_db_override):
    """Test that member count excludes inactive members."""
    conn = DatabaseConnection.get_instance()

    # Create workspace
    workspace_id = workspace_repo.create(
        name='Test Workspace Inactive',
        description='Test inactive members',
        created_by_user_id=test_users['user1_id']
    )

    # Add members
    conn.execute('''
        INSERT INTO workspace_memberships (workspace_id, user_id, role, is_active)
        VALUES (?, ?, 'OWNER', 1)
    ''', (workspace_id, test_users['user1_id']))

    conn.execute('''
        INSERT INTO workspace_memberships (workspace_id, user_id, role, is_active)
        VALUES (?, ?, 'MEMBER_WRITE', 0)
    ''', (workspace_id, test_users['user2_id']))
    conn.commit()

    # Count should only include active members
    count = workspace_repo.get_member_count(workspace_id)
    assert count == 1


def test_get_member_count_empty_workspace(workspace_repo, test_users):
    """Test member count for workspace with no members."""
    workspace_id = workspace_repo.create(
        name='Test Workspace Empty Members',
        description='No members',
        created_by_user_id=test_users['user1_id']
    )

    count = workspace_repo.get_member_count(workspace_id)
    assert count == 0


def test_get_member_count_nonexistent_workspace(workspace_repo):
    """Test member count for non-existent workspace returns 0."""
    count = workspace_repo.get_member_count(99999)
    assert count == 0


def test_workspace_updated_at_trigger(workspace_repo, test_users, test_db_override):
    """Test that updated_at timestamp is automatically updated."""
    import time
    conn = DatabaseConnection.get_instance()

    workspace_id = workspace_repo.create(
        name='Test Workspace Timestamp',
        description='Test timestamp update',
        created_by_user_id=test_users['user1_id']
    )

    # Get initial timestamps
    original = workspace_repo.get_by_id(workspace_id)
    original_updated_at = original['updated_at']

    # Wait a moment to ensure timestamp difference (SQLite CURRENT_TIMESTAMP has second precision)
    time.sleep(1.1)

    # Update workspace
    workspace_repo.update(
        workspace_id=workspace_id,
        updates={'name': 'Test Workspace Updated Timestamp'}
    )

    # Verify updated_at changed
    updated = workspace_repo.get_by_id(workspace_id)
    assert updated['updated_at'] != original_updated_at, \
        f"updated_at should change: {original_updated_at} vs {updated['updated_at']}"
    assert updated['updated_at'] > original_updated_at, \
        f"updated_at should increase: {original_updated_at} -> {updated['updated_at']}"


def test_workspace_foreign_key_constraint(workspace_repo, test_users, test_db_override):
    """Test that foreign key constraints are enforced."""
    conn = DatabaseConnection.get_instance()

    # Create workspace
    workspace_id = workspace_repo.create(
        name='Test Workspace FK',
        description='Test foreign keys',
        created_by_user_id=test_users['user1_id']
    )

    # Verify we cannot delete user who created workspace (RESTRICT constraint)
    with pytest.raises(sqlite3.IntegrityError):
        conn.execute('DELETE FROM users WHERE id = ?', (test_users['user1_id'],))
        conn.commit()


def test_workspace_cascade_on_soft_delete(workspace_repo, test_users, test_db_override):
    """Test that soft deleting workspace doesn't cascade delete memberships."""
    conn = DatabaseConnection.get_instance()

    # Create workspace
    workspace_id = workspace_repo.create(
        name='Test Workspace Cascade',
        description='Test cascade behavior',
        created_by_user_id=test_users['user1_id']
    )

    # Add membership
    conn.execute('''
        INSERT INTO workspace_memberships (workspace_id, user_id, role)
        VALUES (?, ?, 'OWNER')
    ''', (workspace_id, test_users['user1_id']))
    conn.commit()

    # Soft delete workspace
    workspace_repo.delete(workspace_id)

    # Membership should still exist (soft delete doesn't trigger CASCADE)
    cursor = conn.execute('''
        SELECT COUNT(*) as count
        FROM workspace_memberships
        WHERE workspace_id = ?
    ''', (workspace_id,))
    count = cursor.fetchone()['count']
    assert count == 1  # Membership still exists


def test_get_user_workspaces_filters_inactive_workspaces(workspace_repo, test_users, test_db_override):
    """Test that get_user_workspaces excludes inactive workspaces."""
    conn = DatabaseConnection.get_instance()

    # Create workspace
    workspace_id = workspace_repo.create(
        name='Test Workspace Inactive Filter',
        description='Will be deactivated',
        created_by_user_id=test_users['user1_id']
    )

    # Add membership
    conn.execute('''
        INSERT INTO workspace_memberships (workspace_id, user_id, role)
        VALUES (?, ?, 'OWNER')
    ''', (workspace_id, test_users['user1_id']))
    conn.commit()

    # Verify workspace appears in list
    workspaces = workspace_repo.get_user_workspaces(test_users['user1_id'])
    active_workspace = next(
        (ws for ws in workspaces if ws['name'] == 'Test Workspace Inactive Filter'),
        None
    )
    assert active_workspace is not None

    # Soft delete workspace
    workspace_repo.delete(workspace_id)

    # Verify workspace no longer appears in list
    workspaces = workspace_repo.get_user_workspaces(test_users['user1_id'])
    inactive_workspace = next(
        (ws for ws in workspaces if ws['name'] == 'Test Workspace Inactive Filter'),
        None
    )
    assert inactive_workspace is None


if __name__ == '__main__':
    pytest.main([__file__, '-v'])
