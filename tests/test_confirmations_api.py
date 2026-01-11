"""
Unit tests for Duplicate Confirmation API routes.
Tests confirmation listing, decision application, bulk operations, and session status updates.
"""

import pytest
from fastapi.testclient import TestClient
from datetime import datetime, timedelta
import sqlite3
import json

from backend.main import app
from backend.core.security import create_access_token
from src.db.connection import DatabaseConnection
from src.db.repository import (
    DuplicateConfirmationRepository,
    ParsingSessionRepository,
    ProcessedFileRepository,
    CategoryRepository,
    InstitutionRepository,
    TransactionRepository
)
from src.models import Transaction


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
def db_connection():
    """Fixture providing database connection for test setup."""
    conn = DatabaseConnection.get_instance()
    yield conn


@pytest.fixture
def test_data(db_connection):
    """
    Fixture providing test data including session, confirmations, and transactions.

    Creates:
    - Test file record
    - Parsing session with pending_confirmation status
    - Two test transactions
    - Two duplicate confirmations (pending)

    Cleans up after test.
    """
    # Initialize repositories
    file_repo = ProcessedFileRepository(db_connection)
    session_repo = ParsingSessionRepository(db_connection)
    conf_repo = DuplicateConfirmationRepository(db_connection)
    category_repo = CategoryRepository(db_connection)
    institution_repo = InstitutionRepository(db_connection)
    txn_repo = TransactionRepository(db_connection, category_repo, institution_repo)

    # Create test file
    file_id = file_repo.insert_file(
        file_name='test_statement.xlsx',
        file_path='/test/path',
        file_hash='test_hash_' + str(datetime.now().timestamp()),
        file_size=1024,
        institution_id=1
    )

    # Create parsing session
    session_id = session_repo.create_session(
        file_id=file_id,
        parser_type='TEST',
        total_rows=5
    )
    session_repo.update_status(session_id, 'pending_confirmation')

    # Create test transactions
    txn1 = Transaction(
        month='09',
        date='2025.09.13',
        category='식비',
        item='스타벅스 강남점',
        amount=5500,
        source='하나카드'
    )
    txn2 = Transaction(
        month='09',
        date='2025.09.14',
        category='교통',
        item='택시',
        amount=8000,
        source='하나카드'
    )

    txn1_id = txn_repo.insert(txn1)
    txn2_id = txn_repo.insert(txn2)

    # Create duplicate confirmations
    new_txn1_data = json.dumps({
        'month': '09',
        'date': '2025.09.13',
        'category': '식비',
        'item': '스타벅스',
        'amount': 5500,
        'source': '하나카드'
    })

    new_txn2_data = json.dumps({
        'month': '09',
        'date': '2025.09.14',
        'category': '교통',
        'item': '택시 (강남역)',
        'amount': 8000,
        'source': '하나카드'
    })

    conf1_id = conf_repo.create_confirmation(
        session_id=session_id,
        new_transaction_data=new_txn1_data,
        new_transaction_index=1,
        existing_transaction_id=txn1_id,
        confidence_score=85,
        match_fields='["date", "amount", "merchant"]',
        difference_summary='Similar merchant name'
    )

    conf2_id = conf_repo.create_confirmation(
        session_id=session_id,
        new_transaction_data=new_txn2_data,
        new_transaction_index=2,
        existing_transaction_id=txn2_id,
        confidence_score=90,
        match_fields='["date", "amount"]',
        difference_summary='Slightly different merchant description'
    )

    test_data = {
        'file_id': file_id,
        'session_id': session_id,
        'conf1_id': conf1_id,
        'conf2_id': conf2_id,
        'txn1_id': txn1_id,
        'txn2_id': txn2_id
    }

    yield test_data

    # Cleanup
    db_connection.execute(
        'DELETE FROM duplicate_transaction_confirmations WHERE session_id = ?',
        (session_id,)
    )
    db_connection.execute('DELETE FROM transactions WHERE id IN (?, ?)', (txn1_id, txn2_id))
    db_connection.execute('DELETE FROM parsing_sessions WHERE id = ?', (session_id,))
    db_connection.execute('DELETE FROM processed_files WHERE id = ?', (file_id,))
    db_connection.commit()


def test_get_all_confirmations_unauthorized(client):
    """
    Test that getting confirmations without authentication returns 401.

    Verifies authentication is required for this endpoint.
    """
    response = client.get("/api/confirmations")
    assert response.status_code == 401


def test_get_all_confirmations_success(client, auth_token, test_data):
    """
    Test successful retrieval of all pending confirmations.

    Verifies that:
    1. Authenticated request succeeds with 200 status
    2. Response is a list
    3. Confirmations contain expected fields
    4. Only pending confirmations are returned by default
    """
    response = client.get(
        "/api/confirmations",
        headers={"Authorization": f"Bearer {auth_token}"}
    )

    assert response.status_code == 200

    confirmations = response.json()
    assert isinstance(confirmations, list)

    # Find our test confirmations
    test_confirmations = [c for c in confirmations if c['session_id'] == test_data['session_id']]
    assert len(test_confirmations) == 2

    # Verify structure
    for conf in test_confirmations:
        assert 'id' in conf
        assert 'session_id' in conf
        assert 'new_transaction' in conf
        assert 'new_transaction_index' in conf
        assert 'existing_transaction' in conf
        assert 'confidence_score' in conf
        assert 'match_fields' in conf
        assert 'status' in conf
        assert conf['status'] == 'pending'

        # Verify nested transaction objects
        assert isinstance(conf['new_transaction'], dict)
        assert isinstance(conf['existing_transaction'], dict)
        assert isinstance(conf['match_fields'], list)


def test_get_confirmations_by_session_success(client, auth_token, test_data):
    """
    Test successful retrieval of confirmations for a specific session.

    Verifies that:
    1. Authenticated request succeeds with 200 status
    2. Response contains confirmations for the session
    3. Confirmations are ordered by transaction index
    """
    session_id = test_data['session_id']

    response = client.get(
        f"/api/confirmations/session/{session_id}",
        headers={"Authorization": f"Bearer {auth_token}"}
    )

    assert response.status_code == 200

    confirmations = response.json()
    assert isinstance(confirmations, list)
    assert len(confirmations) == 2

    # Verify ordering by transaction index
    assert confirmations[0]['new_transaction_index'] == 1
    assert confirmations[1]['new_transaction_index'] == 2

    # Verify session_id matches
    for conf in confirmations:
        assert conf['session_id'] == session_id


def test_get_confirmations_by_session_not_found(client, auth_token):
    """
    Test that requesting confirmations for non-existent session returns 404.
    """
    response = client.get(
        "/api/confirmations/session/999999",
        headers={"Authorization": f"Bearer {auth_token}"}
    )

    assert response.status_code == 404
    assert 'not found' in response.json()['detail'].lower()


def test_apply_confirmation_skip(client, auth_token, test_data, db_connection):
    """
    Test applying 'skip' action to a single confirmation.

    Verifies that:
    1. Request succeeds with 200 status
    2. Confirmation status updated to 'confirmed_skip'
    3. No new transaction inserted
    4. Session status not updated (other confirmations still pending)
    """
    conf_id = test_data['conf1_id']

    response = client.post(
        f"/api/confirmations/{conf_id}/confirm",
        headers={"Authorization": f"Bearer {auth_token}"},
        json={"action": "skip"}
    )

    assert response.status_code == 200

    updated_conf = response.json()
    assert updated_conf['id'] == conf_id
    assert updated_conf['status'] == 'confirmed_skip'

    # Verify session still pending_confirmation (one more confirmation pending)
    cursor = db_connection.execute(
        'SELECT status FROM parsing_sessions WHERE id = ?',
        (test_data['session_id'],)
    )
    session = cursor.fetchone()
    assert session['status'] == 'pending_confirmation'


def test_apply_confirmation_insert(client, auth_token, test_data, db_connection):
    """
    Test applying 'insert' action to a single confirmation.

    Verifies that:
    1. Request succeeds with 200 status
    2. Confirmation status updated to 'confirmed_insert'
    3. New transaction inserted into database
    4. Session status not updated (other confirmations still pending)
    """
    conf_id = test_data['conf1_id']

    # Count transactions before
    cursor = db_connection.execute('SELECT COUNT(*) as count FROM transactions')
    count_before = cursor.fetchone()['count']

    response = client.post(
        f"/api/confirmations/{conf_id}/confirm",
        headers={"Authorization": f"Bearer {auth_token}"},
        json={"action": "insert"}
    )

    assert response.status_code == 200

    updated_conf = response.json()
    assert updated_conf['id'] == conf_id
    assert updated_conf['status'] == 'confirmed_insert'

    # Verify new transaction inserted
    cursor = db_connection.execute('SELECT COUNT(*) as count FROM transactions')
    count_after = cursor.fetchone()['count']
    assert count_after == count_before + 1

    # Verify session still pending_confirmation
    cursor = db_connection.execute(
        'SELECT status FROM parsing_sessions WHERE id = ?',
        (test_data['session_id'],)
    )
    session = cursor.fetchone()
    assert session['status'] == 'pending_confirmation'


def test_apply_confirmation_completes_session(client, auth_token, test_data, db_connection):
    """
    Test that applying decision to last pending confirmation updates session status.

    Verifies that:
    1. After processing first confirmation, session still pending
    2. After processing second (last) confirmation, session status updates to 'completed'
    """
    conf1_id = test_data['conf1_id']
    conf2_id = test_data['conf2_id']
    session_id = test_data['session_id']

    # Process first confirmation
    response1 = client.post(
        f"/api/confirmations/{conf1_id}/confirm",
        headers={"Authorization": f"Bearer {auth_token}"},
        json={"action": "skip"}
    )
    assert response1.status_code == 200

    # Verify session still pending
    cursor = db_connection.execute(
        'SELECT status FROM parsing_sessions WHERE id = ?',
        (session_id,)
    )
    session = cursor.fetchone()
    assert session['status'] == 'pending_confirmation'

    # Process second (last) confirmation
    response2 = client.post(
        f"/api/confirmations/{conf2_id}/confirm",
        headers={"Authorization": f"Bearer {auth_token}"},
        json={"action": "skip"}
    )
    assert response2.status_code == 200

    # Verify session now completed
    cursor = db_connection.execute(
        'SELECT status FROM parsing_sessions WHERE id = ?',
        (session_id,)
    )
    session = cursor.fetchone()
    assert session['status'] == 'completed'


def test_apply_confirmation_not_found(client, auth_token):
    """
    Test that applying decision to non-existent confirmation returns 404.
    """
    response = client.post(
        "/api/confirmations/999999/confirm",
        headers={"Authorization": f"Bearer {auth_token}"},
        json={"action": "skip"}
    )

    assert response.status_code == 404
    assert 'not found' in response.json()['detail'].lower()


def test_apply_confirmation_invalid_action(client, auth_token, test_data):
    """
    Test that applying invalid action returns 400 validation error.
    """
    conf_id = test_data['conf1_id']

    response = client.post(
        f"/api/confirmations/{conf_id}/confirm",
        headers={"Authorization": f"Bearer {auth_token}"},
        json={"action": "invalid_action"}
    )

    assert response.status_code == 422  # Pydantic validation error


def test_bulk_confirm_skip_all(client, auth_token, test_data, db_connection):
    """
    Test bulk skip operation for all pending confirmations in session.

    Verifies that:
    1. Request succeeds with 200 status
    2. Response contains correct processed count
    3. All confirmations updated to 'confirmed_skip'
    4. Session status updated to 'completed'
    """
    session_id = test_data['session_id']

    response = client.post(
        f"/api/confirmations/session/{session_id}/bulk-confirm",
        headers={"Authorization": f"Bearer {auth_token}"},
        json={"action": "skip"}
    )

    assert response.status_code == 200

    result = response.json()
    assert result['processed_count'] == 2
    assert result['session_id'] == session_id

    # Verify all confirmations updated
    cursor = db_connection.execute(
        'SELECT status FROM duplicate_transaction_confirmations WHERE session_id = ?',
        (session_id,)
    )
    confirmations = cursor.fetchall()
    assert len(confirmations) == 2
    for conf in confirmations:
        assert conf['status'] == 'confirmed_skip'

    # Verify session completed
    cursor = db_connection.execute(
        'SELECT status FROM parsing_sessions WHERE id = ?',
        (session_id,)
    )
    session = cursor.fetchone()
    assert session['status'] == 'completed'


def test_bulk_confirm_insert_all(client, auth_token, test_data, db_connection):
    """
    Test bulk insert operation for all pending confirmations in session.

    Verifies that:
    1. Request succeeds with 200 status
    2. Response contains correct processed count
    3. All confirmations updated to 'confirmed_insert'
    4. All new transactions inserted into database
    5. Session status updated to 'completed'
    """
    session_id = test_data['session_id']

    # Count transactions before
    cursor = db_connection.execute('SELECT COUNT(*) as count FROM transactions')
    count_before = cursor.fetchone()['count']

    response = client.post(
        f"/api/confirmations/session/{session_id}/bulk-confirm",
        headers={"Authorization": f"Bearer {auth_token}"},
        json={"action": "insert"}
    )

    assert response.status_code == 200

    result = response.json()
    assert result['processed_count'] == 2
    assert result['session_id'] == session_id

    # Verify all confirmations updated
    cursor = db_connection.execute(
        'SELECT status FROM duplicate_transaction_confirmations WHERE session_id = ?',
        (session_id,)
    )
    confirmations = cursor.fetchall()
    assert len(confirmations) == 2
    for conf in confirmations:
        assert conf['status'] == 'confirmed_insert'

    # Verify all transactions inserted
    cursor = db_connection.execute('SELECT COUNT(*) as count FROM transactions')
    count_after = cursor.fetchone()['count']
    assert count_after == count_before + 2

    # Verify session completed
    cursor = db_connection.execute(
        'SELECT status FROM parsing_sessions WHERE id = ?',
        (session_id,)
    )
    session = cursor.fetchone()
    assert session['status'] == 'completed'


def test_bulk_confirm_session_not_found(client, auth_token):
    """
    Test that bulk confirm for non-existent session returns 404.
    """
    response = client.post(
        "/api/confirmations/session/999999/bulk-confirm",
        headers={"Authorization": f"Bearer {auth_token}"},
        json={"action": "skip"}
    )

    assert response.status_code == 404
    assert 'not found' in response.json()['detail'].lower()


def test_bulk_confirm_no_pending(client, auth_token, test_data, db_connection):
    """
    Test bulk confirm when no pending confirmations exist (all already processed).

    Verifies that:
    1. Request succeeds with 200 status
    2. Response contains processed_count = 0
    """
    session_id = test_data['session_id']

    # First, process all confirmations
    client.post(
        f"/api/confirmations/session/{session_id}/bulk-confirm",
        headers={"Authorization": f"Bearer {auth_token}"},
        json={"action": "skip"}
    )

    # Try bulk confirm again (should find no pending)
    response = client.post(
        f"/api/confirmations/session/{session_id}/bulk-confirm",
        headers={"Authorization": f"Bearer {auth_token}"},
        json={"action": "skip"}
    )

    assert response.status_code == 200
    result = response.json()
    assert result['processed_count'] == 0
