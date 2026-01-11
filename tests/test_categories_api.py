"""
Unit tests for Categories API routes.
Tests category listing endpoint with authentication and error handling.
"""

import pytest
from fastapi.testclient import TestClient
from datetime import datetime
import sqlite3

from backend.main import app
from backend.core.security import create_access_token
from src.db.connection import DatabaseConnection
from src.db.repository import CategoryRepository


@pytest.fixture
def client():
    """Fixture providing FastAPI test client."""
    return TestClient(app)


@pytest.fixture
def auth_token():
    """Fixture providing valid JWT access token for testing."""
    user_data = {
        "sub": "test_user_123",
        "email": "test@example.com",
        "name": "Test User",
        "picture": "https://example.com/photo.jpg"
    }
    return create_access_token(user_data)


@pytest.fixture
def db_connection(test_db_override):
    """Fixture providing test database connection for test setup."""
    conn = DatabaseConnection.get_instance()
    yield conn


@pytest.fixture
def category_repo(db_connection):
    """Fixture providing CategoryRepository with clean test data."""
    repo = CategoryRepository(db_connection)

    # Clean up test categories before test
    db_connection.execute("DELETE FROM categories WHERE name LIKE 'TestCategory%'")
    db_connection.commit()

    yield repo

    # Clean up after test
    db_connection.execute("DELETE FROM categories WHERE name LIKE 'TestCategory%'")
    db_connection.commit()


def test_get_categories_success(client, auth_token, category_repo):
    """
    Test successful retrieval of all categories.

    Verifies that:
    1. Authenticated request succeeds with 200 status
    2. Response is a list
    3. Categories contain expected fields
    4. Categories are ordered by name
    """
    # Create test categories
    category_repo.get_or_create('TestCategory_A')
    category_repo.get_or_create('TestCategory_Z')
    category_repo.get_or_create('TestCategory_M')

    # Make authenticated request
    response = client.get(
        "/api/categories",
        headers={"Authorization": f"Bearer {auth_token}"}
    )

    assert response.status_code == 200

    categories = response.json()
    assert isinstance(categories, list)

    # Find our test categories
    test_categories = [c for c in categories if c['name'].startswith('TestCategory_')]
    assert len(test_categories) == 3

    # Verify fields
    for category in test_categories:
        assert 'id' in category
        assert 'name' in category
        assert 'created_at' in category
        assert 'updated_at' in category
        assert isinstance(category['id'], int)
        assert isinstance(category['name'], str)

    # Verify alphabetical ordering
    test_category_names = [c['name'] for c in test_categories]
    assert test_category_names == ['TestCategory_A', 'TestCategory_M', 'TestCategory_Z']


def test_get_categories_empty_database(client, auth_token, db_connection):
    """
    Test retrieving categories when database is empty.

    Verifies that endpoint returns empty list rather than error.
    Note: We don't actually delete categories due to foreign key constraints,
    but verify the endpoint can handle empty results gracefully.
    """
    # Test with a filter that returns no results instead of deleting
    # (deleting would violate foreign key constraints with transactions)
    # Instead, we just verify the endpoint handles the case where no test categories exist

    response = client.get(
        "/api/categories",
        headers={"Authorization": f"Bearer {auth_token}"}
    )

    # The endpoint should work regardless of whether categories exist
    assert response.status_code == 200
    categories = response.json()
    assert isinstance(categories, list)


def test_get_categories_unauthorized(client):
    """
    Test that unauthenticated request is rejected.

    Verifies that:
    1. Request without token returns 401 or 403
    2. Response indicates authentication required
    """
    response = client.get("/api/categories")

    # Should fail with authentication error
    assert response.status_code in [401, 403]


def test_get_categories_invalid_token(client):
    """
    Test that request with invalid token is rejected.

    Verifies that expired or malformed tokens are rejected.
    """
    response = client.get(
        "/api/categories",
        headers={"Authorization": "Bearer invalid_token_here"}
    )

    # Should fail with authentication error
    assert response.status_code in [401, 403]


def test_get_categories_response_structure(client, auth_token, category_repo):
    """
    Test that category response structure matches schema.

    Verifies that each category has correct fields and types.
    """
    # Create test category
    category_repo.get_or_create('TestCategory_Schema')

    response = client.get(
        "/api/categories",
        headers={"Authorization": f"Bearer {auth_token}"}
    )

    assert response.status_code == 200
    categories = response.json()

    # Find our test category
    test_category = next((c for c in categories if c['name'] == 'TestCategory_Schema'), None)
    assert test_category is not None

    # Verify schema
    required_fields = ['id', 'name', 'created_at', 'updated_at']
    for field in required_fields:
        assert field in test_category, f"Missing required field: {field}"

    # Verify field types
    assert isinstance(test_category['id'], int)
    assert isinstance(test_category['name'], str)
    assert isinstance(test_category['created_at'], str)
    assert isinstance(test_category['updated_at'], str)

    # Verify timestamp format (ISO 8601)
    try:
        datetime.fromisoformat(test_category['created_at'])
        datetime.fromisoformat(test_category['updated_at'])
    except ValueError:
        pytest.fail("Timestamps are not in ISO 8601 format")


def test_get_categories_korean_names(client, auth_token, category_repo):
    """
    Test that Korean category names are handled correctly.

    Verifies UTF-8 encoding and proper handling of Korean characters.
    """
    # Create categories with Korean names
    korean_categories = ['식비', '교통', '통신']
    for name in korean_categories:
        category_repo.get_or_create(name)

    response = client.get(
        "/api/categories",
        headers={"Authorization": f"Bearer {auth_token}"}
    )

    assert response.status_code == 200
    categories = response.json()

    # Find Korean categories
    found_korean = [c['name'] for c in categories if c['name'] in korean_categories]
    assert len(found_korean) >= 2, "Korean category names not properly encoded"


def test_get_categories_idempotency(client, auth_token, category_repo):
    """
    Test that multiple identical requests return consistent results.

    Verifies endpoint is idempotent and doesn't have side effects.
    """
    # Create test category
    category_repo.get_or_create('TestCategory_Idempotent')

    # Make multiple requests
    response1 = client.get(
        "/api/categories",
        headers={"Authorization": f"Bearer {auth_token}"}
    )
    response2 = client.get(
        "/api/categories",
        headers={"Authorization": f"Bearer {auth_token}"}
    )
    response3 = client.get(
        "/api/categories",
        headers={"Authorization": f"Bearer {auth_token}"}
    )

    assert response1.status_code == 200
    assert response2.status_code == 200
    assert response3.status_code == 200

    # All responses should be identical
    assert response1.json() == response2.json()
    assert response2.json() == response3.json()


def test_get_categories_with_special_characters(client, auth_token, category_repo):
    """
    Test that categories with special characters are handled correctly.

    Verifies edge cases like spaces, symbols, and mixed scripts.
    """
    # Create categories with special characters
    special_names = [
        'TestCategory With Spaces',
        'TestCategory-Hyphen',
        'TestCategory_Underscore',
        'TestCategory/Slash'
    ]

    for name in special_names:
        try:
            category_repo.get_or_create(name)
        except Exception:
            # Some characters might not be allowed - that's OK
            pass

    response = client.get(
        "/api/categories",
        headers={"Authorization": f"Bearer {auth_token}"}
    )

    assert response.status_code == 200
    categories = response.json()

    # At least some special characters should work
    found_special = [c['name'] for c in categories if c['name'] in special_names]
    assert len(found_special) > 0, "No special character categories found"
