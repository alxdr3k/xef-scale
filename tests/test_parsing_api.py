"""
Unit tests for Parsing Sessions API routes.
Tests parsing session listing, detail, and skipped transactions endpoints.
"""

import pytest
from fastapi.testclient import TestClient
from datetime import datetime
import sqlite3
import json

from backend.main import app
from backend.core.security import create_access_token
from src.db.connection import DatabaseConnection
from src.db.repository import (
    ParsingSessionRepository,
    SkippedTransactionRepository,
    ProcessedFileRepository,
    InstitutionRepository
)
from src.models import SkippedTransaction


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
def test_repositories(db_connection):
    """Fixture providing all necessary repositories for tests."""
    parsing_repo = ParsingSessionRepository(db_connection)
    skipped_repo = SkippedTransactionRepository(db_connection)
    file_repo = ProcessedFileRepository(db_connection)
    institution_repo = InstitutionRepository(db_connection)

    # Clean up test data before tests
    db_connection.execute("DELETE FROM skipped_transactions WHERE session_id IN (SELECT id FROM parsing_sessions WHERE file_id IN (SELECT id FROM processed_files WHERE file_name LIKE 'test_%'))")
    db_connection.execute("DELETE FROM parsing_sessions WHERE file_id IN (SELECT id FROM processed_files WHERE file_name LIKE 'test_%')")
    db_connection.execute("DELETE FROM processed_files WHERE file_name LIKE 'test_%'")
    db_connection.commit()

    yield {
        'parsing': parsing_repo,
        'skipped': skipped_repo,
        'file': file_repo,
        'institution': institution_repo
    }

    # Clean up after tests
    db_connection.execute("DELETE FROM skipped_transactions WHERE session_id IN (SELECT id FROM parsing_sessions WHERE file_id IN (SELECT id FROM processed_files WHERE file_name LIKE 'test_%'))")
    db_connection.execute("DELETE FROM parsing_sessions WHERE file_id IN (SELECT id FROM processed_files WHERE file_name LIKE 'test_%')")
    db_connection.execute("DELETE FROM processed_files WHERE file_name LIKE 'test_%'")
    db_connection.commit()


def create_test_session(repos, file_name='test_file.xls', parser_type='HANA', status='completed'):
    """Helper function to create a test parsing session."""
    # Create institution
    institution_id = repos['institution'].get_or_create('TestInstitution', 'BANK')

    # Create processed file
    file_id = repos['file'].insert_file(
        file_name=file_name,
        file_path=f'/inbox/{file_name}',
        file_hash=f'hash_{file_name}',
        file_size=1024,
        institution_id=institution_id,
        processed_at=datetime.now().isoformat()
    )

    # Create parsing session
    session_id = repos['parsing'].create_session(
        file_id=file_id,
        parser_type=parser_type,
        total_rows=100
    )

    # Complete session if status is completed
    if status == 'completed':
        repos['parsing'].complete_session(
            session_id=session_id,
            rows_saved=85,
            rows_skipped=5,
            rows_duplicate=10,
            validation_status='pass',
            validation_notes='All validations passed'
        )

    return session_id, file_id


# ==================== Parsing Sessions List Tests ====================

def test_get_parsing_sessions_success(client, auth_token, test_repositories):
    """
    Test successful retrieval of parsing sessions list.

    Verifies that:
    1. Authenticated request succeeds with 200 status
    2. Response contains sessions array
    3. Pagination metadata is correct
    """
    # Create test sessions
    create_test_session(test_repositories, 'test_session1.xls', 'HANA')
    create_test_session(test_repositories, 'test_session2.csv', 'TOSS')

    response = client.get(
        "/api/parsing-sessions",
        headers={"Authorization": f"Bearer {auth_token}"}
    )

    assert response.status_code == 200

    data = response.json()
    assert 'sessions' in data
    assert 'total' in data
    assert 'page' in data
    assert 'page_size' in data

    assert isinstance(data['sessions'], list)
    assert isinstance(data['total'], int)
    assert data['page'] == 1
    assert data['page_size'] == 50


def test_get_parsing_sessions_pagination(client, auth_token, test_repositories):
    """
    Test pagination of parsing sessions.

    Verifies that page and page_size parameters work correctly.
    """
    # Create multiple test sessions
    for i in range(5):
        create_test_session(test_repositories, f'test_pagination_{i}.xls', 'HANA')

    # Request first page with page_size=2
    response = client.get(
        "/api/parsing-sessions?page=1&page_size=2",
        headers={"Authorization": f"Bearer {auth_token}"}
    )

    assert response.status_code == 200
    data = response.json()

    assert data['page'] == 1
    assert data['page_size'] == 2
    assert len(data['sessions']) <= 2

    # Request second page
    response2 = client.get(
        "/api/parsing-sessions?page=2&page_size=2",
        headers={"Authorization": f"Bearer {auth_token}"}
    )

    assert response2.status_code == 200
    data2 = response2.json()
    assert data2['page'] == 2


def test_get_parsing_sessions_response_structure(client, auth_token, test_repositories):
    """
    Test that parsing session response structure matches schema.

    Verifies all required fields are present with correct types.
    """
    # Create test session
    session_id, file_id = create_test_session(test_repositories, 'test_structure.xls', 'HANA')

    response = client.get(
        "/api/parsing-sessions",
        headers={"Authorization": f"Bearer {auth_token}"}
    )

    assert response.status_code == 200
    data = response.json()

    # Find our test session
    test_session = next((s for s in data['sessions'] if s['id'] == session_id), None)
    assert test_session is not None

    # Verify required fields
    required_fields = [
        'id', 'file_id', 'parser_type', 'started_at', 'completed_at',
        'total_rows_in_file', 'rows_saved', 'rows_skipped', 'rows_duplicate',
        'status', 'validation_status'
    ]
    for field in required_fields:
        assert field in test_session, f"Missing required field: {field}"

    # Verify field types
    assert isinstance(test_session['id'], int)
    assert isinstance(test_session['file_id'], int)
    assert isinstance(test_session['parser_type'], str)
    assert isinstance(test_session['total_rows_in_file'], int)
    assert isinstance(test_session['status'], str)


def test_get_parsing_sessions_unauthorized(client):
    """Test that unauthenticated request is rejected."""
    response = client.get("/api/parsing-sessions")
    assert response.status_code in [401, 403]


def test_get_parsing_sessions_invalid_token(client):
    """Test that request with invalid token is rejected."""
    response = client.get(
        "/api/parsing-sessions",
        headers={"Authorization": "Bearer invalid_token"}
    )
    assert response.status_code in [401, 403]


def test_get_parsing_sessions_invalid_pagination(client, auth_token):
    """
    Test that invalid pagination parameters are rejected.

    Verifies validation of page and page_size parameters.
    """
    # Invalid page (< 1)
    response = client.get(
        "/api/parsing-sessions?page=0",
        headers={"Authorization": f"Bearer {auth_token}"}
    )
    assert response.status_code == 422

    # Invalid page_size (> 200)
    response = client.get(
        "/api/parsing-sessions?page_size=300",
        headers={"Authorization": f"Bearer {auth_token}"}
    )
    assert response.status_code == 422


def test_get_parsing_sessions_empty_database(client, auth_token, db_connection):
    """
    Test retrieving sessions when database is empty.

    Verifies that endpoint handles no results gracefully.
    Note: We don't delete sessions but verify the endpoint works correctly.
    """
    # Just verify the endpoint works - we can't safely delete all sessions
    # due to database constraints without affecting other tests
    response = client.get(
        "/api/parsing-sessions",
        headers={"Authorization": f"Bearer {auth_token}"}
    )

    assert response.status_code == 200
    data = response.json()
    assert 'sessions' in data
    assert 'total' in data
    assert isinstance(data['sessions'], list)
    assert isinstance(data['total'], int)


# ==================== Parsing Session Detail Tests ====================

def test_get_parsing_session_by_id_success(client, auth_token, test_repositories):
    """
    Test successful retrieval of single parsing session.

    Verifies that session detail contains all expected information.
    """
    # Create test session
    session_id, file_id = create_test_session(test_repositories, 'test_detail.xls', 'HANA')

    response = client.get(
        f"/api/parsing-sessions/{session_id}",
        headers={"Authorization": f"Bearer {auth_token}"}
    )

    assert response.status_code == 200
    session = response.json()

    assert session['id'] == session_id
    assert session['file_id'] == file_id
    assert session['parser_type'] == 'HANA'
    assert session['status'] == 'completed'
    assert 'file_name' in session
    assert session['file_name'] == 'test_detail.xls'


def test_get_parsing_session_by_id_not_found(client, auth_token):
    """
    Test that non-existent session returns 404.

    Verifies proper error handling for invalid session IDs.
    """
    # Request non-existent session
    response = client.get(
        "/api/parsing-sessions/999999",
        headers={"Authorization": f"Bearer {auth_token}"}
    )

    assert response.status_code == 404


def test_get_parsing_session_by_id_response_structure(client, auth_token, test_repositories):
    """
    Test that session detail response structure matches schema.

    Verifies all fields including joined data from files and institutions.
    """
    # Create test session
    session_id, file_id = create_test_session(test_repositories, 'test_schema.xls', 'TOSS')

    response = client.get(
        f"/api/parsing-sessions/{session_id}",
        headers={"Authorization": f"Bearer {auth_token}"}
    )

    assert response.status_code == 200
    session = response.json()

    # Verify required fields
    required_fields = [
        'id', 'file_id', 'parser_type', 'started_at', 'completed_at',
        'total_rows_in_file', 'rows_saved', 'rows_skipped', 'rows_duplicate',
        'status', 'validation_status', 'validation_notes',
        'file_name', 'file_hash', 'institution_name', 'institution_type'
    ]
    for field in required_fields:
        assert field in session, f"Missing required field: {field}"


def test_get_parsing_session_by_id_unauthorized(client):
    """Test that unauthenticated request is rejected."""
    response = client.get("/api/parsing-sessions/1")
    assert response.status_code in [401, 403]


def test_get_parsing_session_by_id_invalid_token(client):
    """Test that request with invalid token is rejected."""
    response = client.get(
        "/api/parsing-sessions/1",
        headers={"Authorization": "Bearer invalid_token"}
    )
    assert response.status_code in [401, 403]


# ==================== Skipped Transactions Tests ====================

def test_get_skipped_transactions_success(client, auth_token, test_repositories):
    """
    Test successful retrieval of skipped transactions.

    Verifies that skipped transactions are returned with correct structure.
    """
    # Create test session
    session_id, file_id = create_test_session(test_repositories, 'test_skipped.xls', 'HANA')

    # Add skipped transactions
    skipped_list = [
        SkippedTransaction(
            row_number=5,
            skip_reason='zero_amount',
            merchant_name='Test Store',
            amount=0,
            skip_details='Amount is zero',
            column_data={'col1': 'value1', 'col2': 'value2'}
        ),
        SkippedTransaction(
            row_number=10,
            skip_reason='invalid_date',
            skip_details='Date format invalid'
        )
    ]
    test_repositories['skipped'].batch_insert(session_id, skipped_list)

    response = client.get(
        f"/api/parsing-sessions/{session_id}/skipped",
        headers={"Authorization": f"Bearer {auth_token}"}
    )

    assert response.status_code == 200
    skipped = response.json()

    assert isinstance(skipped, list)
    assert len(skipped) == 2

    # Verify first skipped transaction
    first_skipped = skipped[0]
    assert first_skipped['session_id'] == session_id
    assert first_skipped['row_number'] == 5
    assert first_skipped['skip_reason'] == 'zero_amount'
    assert first_skipped['merchant_name'] == 'Test Store'
    assert first_skipped['amount'] == 0


def test_get_skipped_transactions_empty(client, auth_token, test_repositories):
    """
    Test retrieval when session has no skipped transactions.

    Verifies that empty list is returned rather than error.
    """
    # Create test session without skipped transactions
    session_id, file_id = create_test_session(test_repositories, 'test_no_skipped.xls', 'HANA')

    response = client.get(
        f"/api/parsing-sessions/{session_id}/skipped",
        headers={"Authorization": f"Bearer {auth_token}"}
    )

    assert response.status_code == 200
    skipped = response.json()

    assert isinstance(skipped, list)
    assert len(skipped) == 0


def test_get_skipped_transactions_not_found(client, auth_token):
    """
    Test that non-existent session returns 404.

    Verifies proper error handling for invalid session IDs.
    """
    response = client.get(
        "/api/parsing-sessions/999999/skipped",
        headers={"Authorization": f"Bearer {auth_token}"}
    )

    assert response.status_code == 404


def test_get_skipped_transactions_response_structure(client, auth_token, test_repositories):
    """
    Test that skipped transaction response structure matches schema.

    Verifies all required fields and JSON deserialization of column_data.
    """
    # Create test session with skipped transaction
    session_id, file_id = create_test_session(test_repositories, 'test_skipped_schema.xls', 'HANA')

    skipped_list = [
        SkippedTransaction(
            row_number=3,
            skip_reason='missing_merchant',
            transaction_date='2025.01.10',
            amount=5000,
            skip_details='Merchant name is empty',
            column_data={'date': '2025.01.10', 'amount': '5000', 'merchant': ''}
        )
    ]
    test_repositories['skipped'].batch_insert(session_id, skipped_list)

    response = client.get(
        f"/api/parsing-sessions/{session_id}/skipped",
        headers={"Authorization": f"Bearer {auth_token}"}
    )

    assert response.status_code == 200
    skipped = response.json()

    assert len(skipped) == 1
    first = skipped[0]

    # Verify required fields
    required_fields = ['id', 'session_id', 'row_number', 'skip_reason']
    for field in required_fields:
        assert field in first, f"Missing required field: {field}"

    # Verify column_data is deserialized from JSON
    assert 'column_data' in first
    assert isinstance(first['column_data'], dict)
    assert 'date' in first['column_data']


def test_get_skipped_transactions_ordered_by_row_number(client, auth_token, test_repositories):
    """
    Test that skipped transactions are ordered by row_number.

    Verifies sequential ordering for debugging purposes.
    """
    # Create test session with multiple skipped transactions
    session_id, file_id = create_test_session(test_repositories, 'test_ordered.xls', 'HANA')

    skipped_list = [
        SkippedTransaction(row_number=15, skip_reason='test1'),
        SkippedTransaction(row_number=3, skip_reason='test2'),
        SkippedTransaction(row_number=10, skip_reason='test3'),
    ]
    test_repositories['skipped'].batch_insert(session_id, skipped_list)

    response = client.get(
        f"/api/parsing-sessions/{session_id}/skipped",
        headers={"Authorization": f"Bearer {auth_token}"}
    )

    assert response.status_code == 200
    skipped = response.json()

    # Verify ordering by row_number
    row_numbers = [s['row_number'] for s in skipped]
    assert row_numbers == [3, 10, 15]


def test_get_skipped_transactions_unauthorized(client):
    """Test that unauthenticated request is rejected."""
    response = client.get("/api/parsing-sessions/1/skipped")
    assert response.status_code in [401, 403]


def test_get_skipped_transactions_invalid_token(client):
    """Test that request with invalid token is rejected."""
    response = client.get(
        "/api/parsing-sessions/1/skipped",
        headers={"Authorization": "Bearer invalid_token"}
    )
    assert response.status_code in [401, 403]


# ==================== Edge Cases and Integration Tests ====================

def test_parsing_sessions_with_multiple_parser_types(client, auth_token, test_repositories):
    """
    Test that sessions with different parser types are all returned.

    Verifies support for HANA, TOSS, SHINHAN, etc.
    """
    # Create sessions with different parser types
    create_test_session(test_repositories, 'test_hana.xls', 'HANA')
    create_test_session(test_repositories, 'test_toss.csv', 'TOSS')
    create_test_session(test_repositories, 'test_shinhan.pdf', 'SHINHAN')

    response = client.get(
        "/api/parsing-sessions",
        headers={"Authorization": f"Bearer {auth_token}"}
    )

    assert response.status_code == 200
    data = response.json()

    # Find our test sessions
    parser_types = {s['parser_type'] for s in data['sessions'] if s['file_name'] and s['file_name'].startswith('test_')}
    assert 'HANA' in parser_types
    assert 'TOSS' in parser_types
    assert 'SHINHAN' in parser_types


def test_parsing_session_with_failed_status(client, auth_token, test_repositories):
    """
    Test that failed parsing sessions are properly represented.

    Verifies error_message field is populated for failed sessions.
    """
    # Create institution and file
    institution_id = test_repositories['institution'].get_or_create('TestInstitution', 'BANK')
    file_id = test_repositories['file'].insert_file(
        file_name='test_failed.xls',
        file_path='/inbox/test_failed.xls',
        file_hash='hash_failed',
        file_size=1024,
        institution_id=institution_id,
        processed_at=datetime.now().isoformat()
    )

    # Create failed session
    session_id = test_repositories['parsing'].create_session(
        file_id=file_id,
        parser_type='HANA',
        total_rows=100
    )
    test_repositories['parsing'].fail_session(session_id, 'Invalid file format')

    response = client.get(
        f"/api/parsing-sessions/{session_id}",
        headers={"Authorization": f"Bearer {auth_token}"}
    )

    assert response.status_code == 200
    session = response.json()

    assert session['status'] == 'failed'
    assert session['error_message'] == 'Invalid file format'
