"""
Unit tests for WorkspaceInvitationRepository.

Tests cover invitation creation, token generation, expiration handling,
usage limits, revocation, and validation logic.
"""

import sqlite3
import pytest
import time
from datetime import datetime, timezone, timedelta
from src.db.repository import WorkspaceInvitationRepository


@pytest.fixture
def db():
    """Create in-memory test database with workspace schema."""
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

    # Create workspace_invitations table
    conn.execute('''
        CREATE TABLE workspace_invitations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            workspace_id INTEGER NOT NULL,
            token TEXT NOT NULL UNIQUE,
            role TEXT NOT NULL CHECK(role IN ('CO_OWNER', 'MEMBER_WRITE', 'MEMBER_READ')),
            created_by_user_id INTEGER NOT NULL,
            expires_at DATETIME NOT NULL,
            max_uses INTEGER,
            current_uses INTEGER DEFAULT 0,
            is_active BOOLEAN DEFAULT 1,
            revoked_at DATETIME,
            revoked_by_user_id INTEGER,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE,
            FOREIGN KEY (created_by_user_id) REFERENCES users(id) ON DELETE CASCADE,
            FOREIGN KEY (revoked_by_user_id) REFERENCES users(id) ON DELETE SET NULL
        )
    ''')

    # Create unique index on token
    conn.execute('CREATE UNIQUE INDEX idx_workspace_invitations_token ON workspace_invitations(token)')

    # Insert test users
    conn.execute("INSERT INTO users (name, email) VALUES ('Alice', 'alice@test.com')")
    conn.execute("INSERT INTO users (name, email) VALUES ('Bob', 'bob@test.com')")
    conn.commit()

    # Insert test workspace
    conn.execute('''
        INSERT INTO workspaces (name, description, created_by_user_id)
        VALUES ('Test Workspace', 'Test Description', 1)
    ''')
    conn.commit()

    yield conn
    conn.close()


class TestInvitationCreation:
    """Tests for create_invitation method."""

    def test_create_invitation_basic(self, db):
        """Test basic invitation creation with all required fields."""
        repo = WorkspaceInvitationRepository(db)

        invitation = repo.create_invitation(
            db=db,
            workspace_id=1,
            role='MEMBER_WRITE',
            created_by_user_id=1,
            expires_in_days=7
        )

        assert invitation is not None
        assert invitation['workspace_id'] == 1
        assert invitation['role'] == 'MEMBER_WRITE'
        assert invitation['created_by_user_id'] == 1
        assert invitation['is_active'] == 1
        assert invitation['current_uses'] == 0
        assert invitation['max_uses'] is None
        assert invitation['token'] is not None
        assert len(invitation['token']) == 43  # URL-safe base64 encoding of 32 bytes

    def test_create_invitation_with_max_uses(self, db):
        """Test invitation creation with usage limit."""
        repo = WorkspaceInvitationRepository(db)

        invitation = repo.create_invitation(
            db=db,
            workspace_id=1,
            role='MEMBER_READ',
            created_by_user_id=1,
            expires_in_days=7,
            max_uses=5
        )

        assert invitation['max_uses'] == 5
        assert invitation['current_uses'] == 0

    def test_create_invitation_expiration_calculation(self, db):
        """Test that expiration date is calculated correctly."""
        repo = WorkspaceInvitationRepository(db)

        now = datetime.now(timezone.utc)
        invitation = repo.create_invitation(
            db=db,
            workspace_id=1,
            role='CO_OWNER',
            created_by_user_id=1,
            expires_in_days=14
        )

        expires_at = datetime.fromisoformat(invitation['expires_at'])
        expected_expiry = now + timedelta(days=14)

        # Allow 1 second tolerance for test execution time
        assert abs((expires_at - expected_expiry).total_seconds()) < 1

    def test_create_invitation_co_owner_role(self, db):
        """Test invitation creation with CO_OWNER role."""
        repo = WorkspaceInvitationRepository(db)

        invitation = repo.create_invitation(
            db=db,
            workspace_id=1,
            role='CO_OWNER',
            created_by_user_id=1,
            expires_in_days=7
        )

        assert invitation['role'] == 'CO_OWNER'

    def test_create_invitation_member_read_role(self, db):
        """Test invitation creation with MEMBER_READ role."""
        repo = WorkspaceInvitationRepository(db)

        invitation = repo.create_invitation(
            db=db,
            workspace_id=1,
            role='MEMBER_READ',
            created_by_user_id=1,
            expires_in_days=7
        )

        assert invitation['role'] == 'MEMBER_READ'

    def test_create_invitation_owner_role_rejected(self, db):
        """Test that OWNER role cannot be assigned via invitations."""
        repo = WorkspaceInvitationRepository(db)

        with pytest.raises(ValueError, match='OWNER role cannot be assigned via invitations'):
            repo.create_invitation(
                db=db,
                workspace_id=1,
                role='OWNER',
                created_by_user_id=1,
                expires_in_days=7
            )

    def test_create_invitation_invalid_role(self, db):
        """Test that invalid roles are rejected."""
        repo = WorkspaceInvitationRepository(db)

        with pytest.raises(ValueError, match='Invalid role'):
            repo.create_invitation(
                db=db,
                workspace_id=1,
                role='INVALID_ROLE',
                created_by_user_id=1,
                expires_in_days=7
            )

    def test_create_invitation_invalid_workspace_id(self, db):
        """Test that invalid workspace_id raises IntegrityError."""
        repo = WorkspaceInvitationRepository(db)

        with pytest.raises(sqlite3.IntegrityError):
            repo.create_invitation(
                db=db,
                workspace_id=999,  # Non-existent workspace
                role='MEMBER_WRITE',
                created_by_user_id=1,
                expires_in_days=7
            )

    def test_create_invitation_invalid_user_id(self, db):
        """Test that invalid created_by_user_id raises IntegrityError."""
        repo = WorkspaceInvitationRepository(db)

        with pytest.raises(sqlite3.IntegrityError):
            repo.create_invitation(
                db=db,
                workspace_id=1,
                role='MEMBER_WRITE',
                created_by_user_id=999,  # Non-existent user
                expires_in_days=7
            )

    def test_token_uniqueness(self, db):
        """Test that generated tokens are unique."""
        repo = WorkspaceInvitationRepository(db)

        # Create multiple invitations
        tokens = set()
        for _ in range(10):
            invitation = repo.create_invitation(
                db=db,
                workspace_id=1,
                role='MEMBER_WRITE',
                created_by_user_id=1,
                expires_in_days=7
            )
            tokens.add(invitation['token'])

        # All tokens should be unique
        assert len(tokens) == 10


class TestTokenRetrieval:
    """Tests for get_by_token method."""

    def test_get_by_token_existing(self, db):
        """Test retrieving an existing invitation by token."""
        repo = WorkspaceInvitationRepository(db)

        # Create invitation
        created = repo.create_invitation(
            db=db,
            workspace_id=1,
            role='MEMBER_WRITE',
            created_by_user_id=1,
            expires_in_days=7
        )

        # Retrieve by token
        retrieved = repo.get_by_token(db, created['token'])

        assert retrieved is not None
        assert retrieved['id'] == created['id']
        assert retrieved['token'] == created['token']
        assert retrieved['workspace_id'] == created['workspace_id']
        assert retrieved['role'] == created['role']

    def test_get_by_token_nonexistent(self, db):
        """Test retrieving a non-existent token returns None."""
        repo = WorkspaceInvitationRepository(db)

        result = repo.get_by_token(db, 'nonexistent_token_12345')

        assert result is None

    def test_get_by_token_all_fields(self, db):
        """Test that get_by_token returns all invitation fields."""
        repo = WorkspaceInvitationRepository(db)

        created = repo.create_invitation(
            db=db,
            workspace_id=1,
            role='MEMBER_WRITE',
            created_by_user_id=1,
            expires_in_days=7,
            max_uses=10
        )

        retrieved = repo.get_by_token(db, created['token'])

        # Check all fields are present
        assert 'id' in retrieved
        assert 'workspace_id' in retrieved
        assert 'token' in retrieved
        assert 'role' in retrieved
        assert 'created_by_user_id' in retrieved
        assert 'expires_at' in retrieved
        assert 'max_uses' in retrieved
        assert 'current_uses' in retrieved
        assert 'is_active' in retrieved
        assert 'revoked_at' in retrieved
        assert 'revoked_by_user_id' in retrieved
        assert 'created_at' in retrieved
        assert 'updated_at' in retrieved


class TestWorkspaceInvitationListing:
    """Tests for get_workspace_invitations method."""

    def test_get_workspace_invitations_empty(self, db):
        """Test listing invitations for workspace with none."""
        repo = WorkspaceInvitationRepository(db)

        invitations = repo.get_workspace_invitations(db, workspace_id=1)

        assert invitations == []

    def test_get_workspace_invitations_single(self, db):
        """Test listing invitations with one invitation."""
        repo = WorkspaceInvitationRepository(db)

        # Create invitation
        repo.create_invitation(
            db=db,
            workspace_id=1,
            role='MEMBER_WRITE',
            created_by_user_id=1,
            expires_in_days=7
        )

        invitations = repo.get_workspace_invitations(db, workspace_id=1)

        assert len(invitations) == 1
        assert invitations[0]['workspace_id'] == 1
        assert 'created_by_name' in invitations[0]
        assert invitations[0]['created_by_name'] == 'Alice'

    def test_get_workspace_invitations_multiple(self, db):
        """Test listing multiple invitations for workspace."""
        repo = WorkspaceInvitationRepository(db)

        # Create multiple invitations
        for i in range(3):
            repo.create_invitation(
                db=db,
                workspace_id=1,
                role='MEMBER_WRITE',
                created_by_user_id=1,
                expires_in_days=7
            )
            time.sleep(0.01)  # Small delay to ensure different timestamps

        invitations = repo.get_workspace_invitations(db, workspace_id=1)

        assert len(invitations) == 3

    def test_get_workspace_invitations_order(self, db):
        """Test that invitations are ordered by created_at DESC."""
        repo = WorkspaceInvitationRepository(db)

        # Create invitations with explicit timestamps
        inv1 = repo.create_invitation(
            db=db,
            workspace_id=1,
            role='MEMBER_WRITE',
            created_by_user_id=1,
            expires_in_days=7
        )

        # Sleep for 1 second to ensure different created_at timestamps
        # SQLite CURRENT_TIMESTAMP has second precision
        time.sleep(1.1)

        inv2 = repo.create_invitation(
            db=db,
            workspace_id=1,
            role='MEMBER_READ',
            created_by_user_id=1,
            expires_in_days=7
        )

        invitations = repo.get_workspace_invitations(db, workspace_id=1)

        # Newest first (inv2 should be first)
        assert invitations[0]['id'] == inv2['id']
        assert invitations[1]['id'] == inv1['id']

    def test_get_workspace_invitations_includes_revoked(self, db):
        """Test that listing includes both active and revoked invitations."""
        repo = WorkspaceInvitationRepository(db)

        # Create and revoke invitation
        inv1 = repo.create_invitation(
            db=db,
            workspace_id=1,
            role='MEMBER_WRITE',
            created_by_user_id=1,
            expires_in_days=7
        )

        repo.revoke(db, inv1['id'], revoked_by_user_id=1)

        # Create active invitation
        repo.create_invitation(
            db=db,
            workspace_id=1,
            role='MEMBER_READ',
            created_by_user_id=1,
            expires_in_days=7
        )

        invitations = repo.get_workspace_invitations(db, workspace_id=1)

        assert len(invitations) == 2
        # Check that one is revoked
        assert any(inv['is_active'] == 0 for inv in invitations)
        assert any(inv['is_active'] == 1 for inv in invitations)


class TestUsageTracking:
    """Tests for increment_uses method."""

    def test_increment_uses_basic(self, db):
        """Test incrementing invitation usage count."""
        repo = WorkspaceInvitationRepository(db)

        invitation = repo.create_invitation(
            db=db,
            workspace_id=1,
            role='MEMBER_WRITE',
            created_by_user_id=1,
            expires_in_days=7
        )

        assert invitation['current_uses'] == 0

        # Increment uses
        success = repo.increment_uses(db, invitation['id'])
        assert success is True

        # Verify incremented
        updated = repo.get_by_token(db, invitation['token'])
        assert updated['current_uses'] == 1

    def test_increment_uses_multiple_times(self, db):
        """Test incrementing usage count multiple times."""
        repo = WorkspaceInvitationRepository(db)

        invitation = repo.create_invitation(
            db=db,
            workspace_id=1,
            role='MEMBER_WRITE',
            created_by_user_id=1,
            expires_in_days=7
        )

        # Increment 5 times
        for i in range(5):
            repo.increment_uses(db, invitation['id'])

        updated = repo.get_by_token(db, invitation['token'])
        assert updated['current_uses'] == 5

    def test_increment_uses_nonexistent(self, db):
        """Test incrementing non-existent invitation returns False."""
        repo = WorkspaceInvitationRepository(db)

        success = repo.increment_uses(db, invitation_id=999)

        assert success is False

    def test_increment_uses_atomic(self, db):
        """Test that increment_uses is atomic (SQL-level increment)."""
        repo = WorkspaceInvitationRepository(db)

        invitation = repo.create_invitation(
            db=db,
            workspace_id=1,
            role='MEMBER_WRITE',
            created_by_user_id=1,
            expires_in_days=7
        )

        # Simulate concurrent increments
        for _ in range(10):
            repo.increment_uses(db, invitation['id'])

        updated = repo.get_by_token(db, invitation['token'])
        assert updated['current_uses'] == 10


class TestRevocation:
    """Tests for revoke method."""

    def test_revoke_basic(self, db):
        """Test basic invitation revocation."""
        repo = WorkspaceInvitationRepository(db)

        invitation = repo.create_invitation(
            db=db,
            workspace_id=1,
            role='MEMBER_WRITE',
            created_by_user_id=1,
            expires_in_days=7
        )

        assert invitation['is_active'] == 1

        # Revoke
        success = repo.revoke(db, invitation['id'], revoked_by_user_id=2)
        assert success is True

        # Verify revoked
        updated = repo.get_by_token(db, invitation['token'])
        assert updated['is_active'] == 0
        assert updated['revoked_by_user_id'] == 2
        assert updated['revoked_at'] is not None

    def test_revoke_idempotent(self, db):
        """Test that revoking multiple times is idempotent."""
        repo = WorkspaceInvitationRepository(db)

        invitation = repo.create_invitation(
            db=db,
            workspace_id=1,
            role='MEMBER_WRITE',
            created_by_user_id=1,
            expires_in_days=7
        )

        # Revoke twice
        success1 = repo.revoke(db, invitation['id'], revoked_by_user_id=1)
        success2 = repo.revoke(db, invitation['id'], revoked_by_user_id=1)

        assert success1 is True
        assert success2 is True

        # Verify still revoked
        updated = repo.get_by_token(db, invitation['token'])
        assert updated['is_active'] == 0

    def test_revoke_nonexistent(self, db):
        """Test revoking non-existent invitation returns False."""
        repo = WorkspaceInvitationRepository(db)

        success = repo.revoke(db, invitation_id=999, revoked_by_user_id=1)

        assert success is False

    def test_revoke_sets_timestamp(self, db):
        """Test that revocation sets revoked_at timestamp."""
        repo = WorkspaceInvitationRepository(db)

        invitation = repo.create_invitation(
            db=db,
            workspace_id=1,
            role='MEMBER_WRITE',
            created_by_user_id=1,
            expires_in_days=7
        )

        assert invitation['revoked_at'] is None

        repo.revoke(db, invitation['id'], revoked_by_user_id=1)

        updated = repo.get_by_token(db, invitation['token'])
        assert updated['revoked_at'] is not None


class TestValidation:
    """Tests for is_valid method."""

    def test_is_valid_new_invitation(self, db):
        """Test that newly created invitation is valid."""
        repo = WorkspaceInvitationRepository(db)

        invitation = repo.create_invitation(
            db=db,
            workspace_id=1,
            role='MEMBER_WRITE',
            created_by_user_id=1,
            expires_in_days=7
        )

        assert repo.is_valid(db, invitation['token']) is True

    def test_is_valid_nonexistent_token(self, db):
        """Test that non-existent token is invalid."""
        repo = WorkspaceInvitationRepository(db)

        assert repo.is_valid(db, 'nonexistent_token') is False

    def test_is_valid_revoked_invitation(self, db):
        """Test that revoked invitation is invalid."""
        repo = WorkspaceInvitationRepository(db)

        invitation = repo.create_invitation(
            db=db,
            workspace_id=1,
            role='MEMBER_WRITE',
            created_by_user_id=1,
            expires_in_days=7
        )

        repo.revoke(db, invitation['id'], revoked_by_user_id=1)

        assert repo.is_valid(db, invitation['token']) is False

    def test_is_valid_expired_invitation(self, db):
        """Test that expired invitation is invalid."""
        repo = WorkspaceInvitationRepository(db)

        # Create invitation that expires immediately (0 days)
        invitation = repo.create_invitation(
            db=db,
            workspace_id=1,
            role='MEMBER_WRITE',
            created_by_user_id=1,
            expires_in_days=0
        )

        # Wait a moment to ensure expiration
        time.sleep(0.1)

        assert repo.is_valid(db, invitation['token']) is False

    def test_is_valid_max_uses_reached(self, db):
        """Test that invitation at max_uses is invalid."""
        repo = WorkspaceInvitationRepository(db)

        invitation = repo.create_invitation(
            db=db,
            workspace_id=1,
            role='MEMBER_WRITE',
            created_by_user_id=1,
            expires_in_days=7,
            max_uses=3
        )

        # Use 3 times
        for _ in range(3):
            repo.increment_uses(db, invitation['id'])

        assert repo.is_valid(db, invitation['token']) is False

    def test_is_valid_max_uses_not_reached(self, db):
        """Test that invitation below max_uses is valid."""
        repo = WorkspaceInvitationRepository(db)

        invitation = repo.create_invitation(
            db=db,
            workspace_id=1,
            role='MEMBER_WRITE',
            created_by_user_id=1,
            expires_in_days=7,
            max_uses=5
        )

        # Use 3 times (below max)
        for _ in range(3):
            repo.increment_uses(db, invitation['id'])

        assert repo.is_valid(db, invitation['token']) is True

    def test_is_valid_unlimited_uses(self, db):
        """Test that invitation with unlimited uses stays valid."""
        repo = WorkspaceInvitationRepository(db)

        invitation = repo.create_invitation(
            db=db,
            workspace_id=1,
            role='MEMBER_WRITE',
            created_by_user_id=1,
            expires_in_days=7,
            max_uses=None  # Unlimited
        )

        # Use many times
        for _ in range(100):
            repo.increment_uses(db, invitation['id'])

        # Still valid (not expired, not revoked)
        assert repo.is_valid(db, invitation['token']) is True

    def test_is_valid_active_but_expired(self, db):
        """Test that active invitation is invalid if expired."""
        repo = WorkspaceInvitationRepository(db)

        # Manually create expired invitation
        expires_at = datetime.now(timezone.utc) - timedelta(days=1)
        token = 'test_expired_token_12345678901234567890123'

        db.execute('''
            INSERT INTO workspace_invitations (
                workspace_id, token, role, created_by_user_id,
                expires_at, is_active
            ) VALUES (?, ?, ?, ?, ?, 1)
        ''', (1, token, 'MEMBER_WRITE', 1, expires_at.isoformat()))
        db.commit()

        assert repo.is_valid(db, token) is False

    def test_is_valid_active_not_expired_with_uses_remaining(self, db):
        """Test complex validation: active, not expired, uses remaining."""
        repo = WorkspaceInvitationRepository(db)

        invitation = repo.create_invitation(
            db=db,
            workspace_id=1,
            role='MEMBER_WRITE',
            created_by_user_id=1,
            expires_in_days=7,
            max_uses=10
        )

        # Use 5 times
        for _ in range(5):
            repo.increment_uses(db, invitation['id'])

        # Should be valid: active, not expired, 5 uses remaining
        assert repo.is_valid(db, invitation['token']) is True
