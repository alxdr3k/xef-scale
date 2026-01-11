"""
Unit tests for UserRepository.
Tests user account management including CRUD operations and OAuth token handling.
"""

import sqlite3
import pytest
from datetime import datetime
from src.db.connection import DatabaseConnection
from src.db.repository import UserRepository


@pytest.fixture
def user_repo(test_db_override):
    """Fixture providing UserRepository with test database connection."""
    conn = DatabaseConnection.get_instance()
    repo = UserRepository(conn)

    # Clean up test users before each test
    conn.execute("DELETE FROM users WHERE email LIKE '%@test.example.com'")
    conn.commit()

    yield repo

    # Clean up after test
    conn.execute("DELETE FROM users WHERE email LIKE '%@test.example.com'")
    conn.commit()


def test_create_user(user_repo):
    """Test creating a new user account."""
    user_id = user_repo.create_user(
        email='john@test.example.com',
        google_id='google_123',
        name='John Doe',
        profile_picture_url='https://example.com/photo.jpg',
        access_token='encrypted_access_token',
        refresh_token='encrypted_refresh_token',
        token_expires_at='2026-01-12T12:00:00'
    )

    assert user_id > 0

    # Verify user was created
    user = user_repo.get_by_id(user_id)
    assert user is not None
    assert user['email'] == 'john@test.example.com'
    assert user['google_id'] == 'google_123'
    assert user['name'] == 'John Doe'
    assert user['is_active'] == 1
    assert user['access_token'] == 'encrypted_access_token'
    assert user['refresh_token'] == 'encrypted_refresh_token'


def test_create_duplicate_email(user_repo):
    """Test that duplicate email raises IntegrityError."""
    user_repo.create_user(
        email='duplicate@test.example.com',
        google_id='google_456',
        name='First User'
    )

    # Attempt to create user with same email should fail
    with pytest.raises(sqlite3.IntegrityError):
        user_repo.create_user(
            email='duplicate@test.example.com',
            google_id='google_789',
            name='Second User'
        )


def test_get_by_email(user_repo):
    """Test retrieving user by email address."""
    user_id = user_repo.create_user(
        email='lookup@test.example.com',
        google_id='google_lookup',
        name='Lookup User'
    )

    user = user_repo.get_by_email('lookup@test.example.com')
    assert user is not None
    assert user['id'] == user_id
    assert user['name'] == 'Lookup User'

    # Non-existent email should return None
    user = user_repo.get_by_email('nonexistent@test.example.com')
    assert user is None


def test_get_by_google_id(user_repo):
    """Test retrieving user by Google ID."""
    user_id = user_repo.create_user(
        email='oauth@test.example.com',
        google_id='google_oauth_123',
        name='OAuth User'
    )

    user = user_repo.get_by_google_id('google_oauth_123')
    assert user is not None
    assert user['id'] == user_id
    assert user['email'] == 'oauth@test.example.com'

    # Non-existent google_id should return None
    user = user_repo.get_by_google_id('nonexistent_google_id')
    assert user is None


def test_update_tokens(user_repo):
    """Test updating OAuth tokens."""
    user_id = user_repo.create_user(
        email='token@test.example.com',
        google_id='google_token',
        name='Token User',
        access_token='old_access_token',
        refresh_token='old_refresh_token'
    )

    # Update tokens
    user_repo.update_tokens(
        user_id=user_id,
        access_token='new_access_token',
        refresh_token='new_refresh_token',
        token_expires_at='2026-01-13T12:00:00'
    )

    user = user_repo.get_by_id(user_id)
    assert user['access_token'] == 'new_access_token'
    assert user['refresh_token'] == 'new_refresh_token'
    assert user['token_expires_at'] == '2026-01-13T12:00:00'


def test_update_tokens_preserve_refresh(user_repo):
    """Test updating access token while preserving refresh token."""
    user_id = user_repo.create_user(
        email='preserve@test.example.com',
        google_id='google_preserve',
        name='Preserve User',
        access_token='old_access',
        refresh_token='keep_this_refresh'
    )

    # Update only access token (refresh_token=None should preserve existing)
    user_repo.update_tokens(
        user_id=user_id,
        access_token='new_access',
        refresh_token=None,
        token_expires_at='2026-01-14T12:00:00'
    )

    user = user_repo.get_by_id(user_id)
    assert user['access_token'] == 'new_access'
    assert user['refresh_token'] == 'keep_this_refresh'  # Preserved


def test_update_profile(user_repo):
    """Test updating user profile information."""
    user_id = user_repo.create_user(
        email='profile@test.example.com',
        google_id='google_profile',
        name='Old Name',
        profile_picture_url='https://old.com/photo.jpg'
    )

    # Update profile
    user_repo.update_profile(
        user_id=user_id,
        name='New Name',
        profile_picture_url='https://new.com/photo.jpg'
    )

    user = user_repo.get_by_id(user_id)
    assert user['name'] == 'New Name'
    assert user['profile_picture_url'] == 'https://new.com/photo.jpg'


def test_update_last_login(user_repo):
    """Test updating last login timestamp."""
    user_id = user_repo.create_user(
        email='login@test.example.com',
        google_id='google_login',
        name='Login User'
    )

    # Initially last_login_at should be None
    user = user_repo.get_by_id(user_id)
    assert user['last_login_at'] is None

    # Update last login
    user_repo.update_last_login(user_id)

    user = user_repo.get_by_id(user_id)
    assert user['last_login_at'] is not None
    # Verify timestamp is recent (within last minute)
    last_login = datetime.fromisoformat(user['last_login_at'])
    assert (datetime.now() - last_login).total_seconds() < 60


def test_deactivate_user(user_repo):
    """Test deactivating user account."""
    user_id = user_repo.create_user(
        email='deactivate@test.example.com',
        google_id='google_deactivate',
        name='Deactivate User'
    )

    # Initially is_active should be 1
    user = user_repo.get_by_id(user_id)
    assert user['is_active'] == 1

    # Deactivate user
    user_repo.deactivate_user(user_id)

    user = user_repo.get_by_id(user_id)
    assert user['is_active'] == 0


def test_reactivate_user(user_repo):
    """Test reactivating user account."""
    user_id = user_repo.create_user(
        email='reactivate@test.example.com',
        google_id='google_reactivate',
        name='Reactivate User'
    )

    # Deactivate then reactivate
    user_repo.deactivate_user(user_id)
    user_repo.reactivate_user(user_id)

    user = user_repo.get_by_id(user_id)
    assert user['is_active'] == 1


def test_get_all_active_users(user_repo):
    """Test retrieving all active users."""
    # Create multiple users
    user_repo.create_user(
        email='active1@test.example.com',
        google_id='google_active1',
        name='Active User 1'
    )
    user_repo.create_user(
        email='active2@test.example.com',
        google_id='google_active2',
        name='Active User 2'
    )
    user_id_3 = user_repo.create_user(
        email='inactive@test.example.com',
        google_id='google_inactive',
        name='Inactive User'
    )

    # Deactivate one user
    user_repo.deactivate_user(user_id_3)

    # Get all active users
    active_users = user_repo.get_all_active_users()

    # Should only return active users
    test_users = [u for u in active_users if u['email'].endswith('@test.example.com')]
    assert len(test_users) >= 2
    emails = [u['email'] for u in test_users]
    assert 'active1@test.example.com' in emails
    assert 'active2@test.example.com' in emails
    assert 'inactive@test.example.com' not in emails


def test_count_active_users(user_repo):
    """Test counting active users."""
    # Get initial count
    initial_count = user_repo.count_active_users()

    # Create test users
    user_repo.create_user(
        email='count1@test.example.com',
        google_id='google_count1',
        name='Count User 1'
    )
    user_repo.create_user(
        email='count2@test.example.com',
        google_id='google_count2',
        name='Count User 2'
    )

    # Count should increase by 2
    new_count = user_repo.count_active_users()
    assert new_count == initial_count + 2


if __name__ == '__main__':
    pytest.main([__file__, '-v'])
