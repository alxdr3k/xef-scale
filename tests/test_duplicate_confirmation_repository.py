"""
Unit tests for DuplicateConfirmationRepository.
Tests duplicate transaction confirmation management including creation, retrieval,
user decision application, and expiration cleanup.
"""

import sqlite3
import pytest
import json
from datetime import datetime, timedelta
from src.db.connection import DatabaseConnection
from src.db.repository import (
    DuplicateConfirmationRepository,
    CategoryRepository,
    InstitutionRepository,
    TransactionRepository,
    ParsingSessionRepository,
    ProcessedFileRepository
)
from src.models import Transaction


@pytest.fixture
def test_db(test_db_override):
    """Fixture providing test database connection with cleanup."""
    conn = DatabaseConnection.get_instance()

    # Clean up test data before each test
    conn.execute("DELETE FROM duplicate_transaction_confirmations")
    conn.execute("DELETE FROM parsing_sessions")
    conn.execute("DELETE FROM processed_files")
    conn.execute("DELETE FROM transactions")
    conn.execute("DELETE FROM categories WHERE name LIKE 'Test%'")
    conn.execute("DELETE FROM financial_institutions WHERE name LIKE 'Test%'")
    conn.commit()

    yield conn

    # Clean up after test
    conn.execute("DELETE FROM duplicate_transaction_confirmations")
    conn.execute("DELETE FROM parsing_sessions")
    conn.execute("DELETE FROM processed_files")
    conn.execute("DELETE FROM transactions")
    conn.execute("DELETE FROM categories WHERE name LIKE 'Test%'")
    conn.execute("DELETE FROM financial_institutions WHERE name LIKE 'Test%'")
    conn.commit()


@pytest.fixture
def dup_conf_repo(test_db):
    """Fixture providing DuplicateConfirmationRepository."""
    return DuplicateConfirmationRepository(test_db)


@pytest.fixture
def setup_test_data(test_db):
    """
    Fixture that sets up test data including:
    - Category and institution
    - Processed file
    - Parsing session
    - Existing transaction

    Returns dict with all created IDs.
    """
    category_repo = CategoryRepository(test_db)
    institution_repo = InstitutionRepository(test_db)
    txn_repo = TransactionRepository(test_db, category_repo, institution_repo)
    file_repo = ProcessedFileRepository(test_db)
    session_repo = ParsingSessionRepository(test_db)

    # Create category and institution
    category_id = category_repo.get_or_create('Test식비')
    institution_id = institution_repo.get_or_create('Test카드', 'CARD')

    # Create processed file
    file_id = file_repo.insert_file(
        file_name='test_statement.xls',
        file_path='/inbox/test_statement.xls',
        file_hash='test_hash_123',
        file_size=1024,
        institution_id=institution_id,
        processed_at=datetime.now().isoformat()
    )

    # Create parsing session
    session_id = session_repo.create_session(
        file_id=file_id,
        parser_type='TEST',
        total_rows=100
    )

    # Create existing transaction
    txn = Transaction(
        month='09',
        date='2025.09.13',
        category='Test식비',
        item='Test스타벅스',
        amount=5000,
        source='Test카드'
    )
    existing_txn_id = txn_repo.insert(txn)

    return {
        'category_id': category_id,
        'institution_id': institution_id,
        'file_id': file_id,
        'session_id': session_id,
        'existing_txn_id': existing_txn_id
    }


def test_create_confirmation(dup_conf_repo, setup_test_data):
    """Test creating a new duplicate confirmation."""
    session_id = setup_test_data['session_id']
    existing_txn_id = setup_test_data['existing_txn_id']

    new_txn_data = json.dumps({
        'month': '09',
        'date': '2025.09.13',
        'category': 'Test식비',
        'item': 'Test스타벅스 강남점',
        'amount': 5000,
        'source': 'Test카드'
    })

    confirmation_id = dup_conf_repo.create_confirmation(
        session_id=session_id,
        new_transaction_data=new_txn_data,
        new_transaction_index=5,
        existing_transaction_id=existing_txn_id,
        confidence_score=85,
        match_fields='["date", "amount", "merchant"]',
        difference_summary='Similar merchant name'
    )

    assert confirmation_id > 0

    # Verify confirmation was created
    conf = dup_conf_repo.get_by_id(confirmation_id)
    assert conf is not None
    assert conf['session_id'] == session_id
    assert conf['new_transaction_index'] == 5
    assert conf['existing_transaction_id'] == existing_txn_id
    assert conf['confidence_score'] == 85
    assert conf['status'] == 'pending'
    assert conf['new_transaction_data'] == new_txn_data

    # Verify expires_at is set to ~30 days from now
    created_at = datetime.fromisoformat(conf['created_at'])
    expires_at = datetime.fromisoformat(conf['expires_at'])
    delta = expires_at - created_at
    assert 29 <= delta.days <= 31  # Allow some tolerance


def test_create_confirmation_invalid_confidence(dup_conf_repo, setup_test_data):
    """Test that invalid confidence_score raises ValueError."""
    session_id = setup_test_data['session_id']
    existing_txn_id = setup_test_data['existing_txn_id']

    # Test confidence > 100
    with pytest.raises(ValueError, match="confidence_score"):
        dup_conf_repo.create_confirmation(
            session_id=session_id,
            new_transaction_data='{}',
            new_transaction_index=1,
            existing_transaction_id=existing_txn_id,
            confidence_score=150,
            match_fields='[]',
            difference_summary='Test'
        )

    # Test confidence < 0
    with pytest.raises(ValueError, match="confidence_score"):
        dup_conf_repo.create_confirmation(
            session_id=session_id,
            new_transaction_data='{}',
            new_transaction_index=1,
            existing_transaction_id=existing_txn_id,
            confidence_score=-10,
            match_fields='[]',
            difference_summary='Test'
        )


def test_get_by_session(dup_conf_repo, setup_test_data):
    """Test retrieving all confirmations for a session."""
    session_id = setup_test_data['session_id']
    existing_txn_id = setup_test_data['existing_txn_id']

    # Create multiple confirmations
    for i in range(3):
        new_txn_data = json.dumps({
            'month': '09',
            'date': '2025.09.13',
            'category': 'Test식비',
            'item': f'Test매장{i}',
            'amount': 5000 + i * 1000,
            'source': 'Test카드'
        })

        dup_conf_repo.create_confirmation(
            session_id=session_id,
            new_transaction_data=new_txn_data,
            new_transaction_index=i,
            existing_transaction_id=existing_txn_id,
            confidence_score=80 + i,
            match_fields='["date", "amount"]',
            difference_summary=f'Test difference {i}'
        )

    # Retrieve all confirmations for session
    confirmations = dup_conf_repo.get_by_session(session_id)

    assert len(confirmations) == 3

    # Verify ordering by new_transaction_index
    for i, conf in enumerate(confirmations):
        assert conf['new_transaction_index'] == i
        assert conf['session_id'] == session_id
        # Verify joined fields
        assert conf['existing_merchant_name'] == 'Test스타벅스'
        assert conf['existing_amount'] == 5000
        assert conf['existing_category_name'] == 'Test식비'
        assert conf['existing_institution_name'] == 'Test카드'


def test_get_by_session_empty(dup_conf_repo, setup_test_data):
    """Test get_by_session returns empty list when no confirmations exist."""
    session_id = setup_test_data['session_id']

    confirmations = dup_conf_repo.get_by_session(session_id)
    assert confirmations == []


def test_get_pending_count_by_session(dup_conf_repo, setup_test_data):
    """Test counting pending confirmations for a session."""
    session_id = setup_test_data['session_id']
    existing_txn_id = setup_test_data['existing_txn_id']

    # Initially no pending confirmations
    assert dup_conf_repo.get_pending_count_by_session(session_id) == 0

    # Create 3 pending confirmations
    for i in range(3):
        dup_conf_repo.create_confirmation(
            session_id=session_id,
            new_transaction_data='{}',
            new_transaction_index=i,
            existing_transaction_id=existing_txn_id,
            confidence_score=80,
            match_fields='[]',
            difference_summary='Test'
        )

    assert dup_conf_repo.get_pending_count_by_session(session_id) == 3

    # Confirm one - pending count should decrease
    confirmations = dup_conf_repo.get_by_session(session_id)
    dup_conf_repo.apply_user_decision(
        confirmations[0]['id'],
        'skip',
        'test_user@example.com'
    )

    assert dup_conf_repo.get_pending_count_by_session(session_id) == 2


def test_apply_user_decision_skip(dup_conf_repo, setup_test_data, test_db):
    """Test applying 'skip' user decision."""
    session_id = setup_test_data['session_id']
    existing_txn_id = setup_test_data['existing_txn_id']

    new_txn_data = json.dumps({
        'month': '09',
        'date': '2025.09.13',
        'category': 'Test식비',
        'item': 'Test매장',
        'amount': 5000,
        'source': 'Test카드'
    })

    confirmation_id = dup_conf_repo.create_confirmation(
        session_id=session_id,
        new_transaction_data=new_txn_data,
        new_transaction_index=1,
        existing_transaction_id=existing_txn_id,
        confidence_score=90,
        match_fields='["date", "amount"]',
        difference_summary='Test'
    )

    # Count transactions before decision
    cursor = test_db.execute('SELECT COUNT(*) as count FROM transactions')
    before_count = cursor.fetchone()['count']

    # Apply skip decision
    updated = dup_conf_repo.apply_user_decision(
        confirmation_id,
        'skip',
        'test_user@example.com'
    )

    # Verify status updated
    assert updated['status'] == 'confirmed_skip'
    assert updated['user_action'] == 'skip'
    assert updated['user_id'] == 'test_user@example.com'
    assert updated['decided_at'] is not None

    # Verify no new transaction was inserted
    cursor = test_db.execute('SELECT COUNT(*) as count FROM transactions')
    after_count = cursor.fetchone()['count']
    assert after_count == before_count


def test_apply_user_decision_insert(dup_conf_repo, setup_test_data, test_db):
    """Test applying 'insert' user decision."""
    session_id = setup_test_data['session_id']
    existing_txn_id = setup_test_data['existing_txn_id']

    new_txn_data = json.dumps({
        'month': '09',
        'date': '2025.09.14',
        'category': 'Test식비',
        'item': 'Test새매장',
        'amount': 7000,
        'source': 'Test카드'
    })

    confirmation_id = dup_conf_repo.create_confirmation(
        session_id=session_id,
        new_transaction_data=new_txn_data,
        new_transaction_index=2,
        existing_transaction_id=existing_txn_id,
        confidence_score=70,
        match_fields='["merchant"]',
        difference_summary='Different date and amount'
    )

    # Count transactions before decision
    cursor = test_db.execute('SELECT COUNT(*) as count FROM transactions')
    before_count = cursor.fetchone()['count']

    # Apply insert decision
    updated = dup_conf_repo.apply_user_decision(
        confirmation_id,
        'insert',
        'test_user@example.com'
    )

    # Verify status updated
    assert updated['status'] == 'confirmed_insert'
    assert updated['user_action'] == 'insert'
    assert updated['user_id'] == 'test_user@example.com'

    # Verify new transaction was inserted
    cursor = test_db.execute('SELECT COUNT(*) as count FROM transactions')
    after_count = cursor.fetchone()['count']
    assert after_count == before_count + 1

    # Verify transaction details
    cursor = test_db.execute('''
        SELECT t.*, c.name as category_name, fi.name as institution_name
        FROM transactions t
        JOIN categories c ON t.category_id = c.id
        JOIN financial_institutions fi ON t.institution_id = fi.id
        WHERE t.merchant_name = 'Test새매장'
    ''')
    new_txn = cursor.fetchone()
    assert new_txn is not None
    assert new_txn['amount'] == 7000
    assert new_txn['category_name'] == 'Test식비'
    assert new_txn['institution_name'] == 'Test카드'


def test_apply_user_decision_merge(dup_conf_repo, setup_test_data, test_db):
    """Test applying 'merge' user decision (placeholder implementation)."""
    session_id = setup_test_data['session_id']
    existing_txn_id = setup_test_data['existing_txn_id']

    confirmation_id = dup_conf_repo.create_confirmation(
        session_id=session_id,
        new_transaction_data='{}',
        new_transaction_index=3,
        existing_transaction_id=existing_txn_id,
        confidence_score=95,
        match_fields='[]',
        difference_summary='Test'
    )

    # Apply merge decision
    updated = dup_conf_repo.apply_user_decision(
        confirmation_id,
        'merge',
        'test_user@example.com'
    )

    # Verify status updated
    assert updated['status'] == 'confirmed_merge'
    assert updated['user_action'] == 'merge'
    assert updated['user_id'] == 'test_user@example.com'


def test_apply_user_decision_invalid_action(dup_conf_repo, setup_test_data):
    """Test that invalid action raises ValueError."""
    session_id = setup_test_data['session_id']
    existing_txn_id = setup_test_data['existing_txn_id']

    confirmation_id = dup_conf_repo.create_confirmation(
        session_id=session_id,
        new_transaction_data='{}',
        new_transaction_index=1,
        existing_transaction_id=existing_txn_id,
        confidence_score=80,
        match_fields='[]',
        difference_summary='Test'
    )

    with pytest.raises(ValueError, match="Invalid action"):
        dup_conf_repo.apply_user_decision(
            confirmation_id,
            'invalid_action',
            'test_user@example.com'
        )


def test_apply_user_decision_not_found(dup_conf_repo):
    """Test that non-existent confirmation raises ValueError."""
    with pytest.raises(ValueError, match="Confirmation not found"):
        dup_conf_repo.apply_user_decision(
            99999,
            'skip',
            'test_user@example.com'
        )


def test_get_by_id(dup_conf_repo, setup_test_data):
    """Test retrieving confirmation by ID."""
    session_id = setup_test_data['session_id']
    existing_txn_id = setup_test_data['existing_txn_id']

    confirmation_id = dup_conf_repo.create_confirmation(
        session_id=session_id,
        new_transaction_data='{"test": "data"}',
        new_transaction_index=1,
        existing_transaction_id=existing_txn_id,
        confidence_score=75,
        match_fields='["date"]',
        difference_summary='Test difference'
    )

    conf = dup_conf_repo.get_by_id(confirmation_id)
    assert conf is not None
    assert conf['id'] == confirmation_id
    assert conf['confidence_score'] == 75
    assert conf['new_transaction_data'] == '{"test": "data"}'

    # Non-existent ID should return None
    conf = dup_conf_repo.get_by_id(99999)
    assert conf is None


def test_cleanup_expired(dup_conf_repo, setup_test_data, test_db):
    """Test expiring old pending confirmations."""
    session_id = setup_test_data['session_id']
    existing_txn_id = setup_test_data['existing_txn_id']

    # Create confirmation with past expiration
    confirmation_id = dup_conf_repo.create_confirmation(
        session_id=session_id,
        new_transaction_data='{}',
        new_transaction_index=1,
        existing_transaction_id=existing_txn_id,
        confidence_score=80,
        match_fields='[]',
        difference_summary='Test'
    )

    # Manually set expires_at to past date
    past_date = (datetime.now() - timedelta(days=1)).isoformat()
    test_db.execute(
        'UPDATE duplicate_transaction_confirmations SET expires_at = ? WHERE id = ?',
        (past_date, confirmation_id)
    )
    test_db.commit()

    # Verify it's pending
    conf = dup_conf_repo.get_by_id(confirmation_id)
    assert conf['status'] == 'pending'

    # Run cleanup
    expired_count = dup_conf_repo.cleanup_expired()
    assert expired_count == 1

    # Verify status changed to expired
    conf = dup_conf_repo.get_by_id(confirmation_id)
    assert conf['status'] == 'expired'

    # Run cleanup again - should find nothing
    expired_count = dup_conf_repo.cleanup_expired()
    assert expired_count == 0


def test_cleanup_expired_does_not_affect_confirmed(dup_conf_repo, setup_test_data, test_db):
    """Test that cleanup_expired only affects pending confirmations."""
    session_id = setup_test_data['session_id']
    existing_txn_id = setup_test_data['existing_txn_id']

    # Create and confirm a confirmation
    confirmation_id = dup_conf_repo.create_confirmation(
        session_id=session_id,
        new_transaction_data='{}',
        new_transaction_index=1,
        existing_transaction_id=existing_txn_id,
        confidence_score=80,
        match_fields='[]',
        difference_summary='Test'
    )

    dup_conf_repo.apply_user_decision(confirmation_id, 'skip', 'test_user@example.com')

    # Manually set expires_at to past date
    past_date = (datetime.now() - timedelta(days=1)).isoformat()
    test_db.execute(
        'UPDATE duplicate_transaction_confirmations SET expires_at = ? WHERE id = ?',
        (past_date, confirmation_id)
    )
    test_db.commit()

    # Run cleanup
    expired_count = dup_conf_repo.cleanup_expired()
    assert expired_count == 0

    # Verify status is still confirmed_skip
    conf = dup_conf_repo.get_by_id(confirmation_id)
    assert conf['status'] == 'confirmed_skip'


def test_get_all_pending(dup_conf_repo, setup_test_data):
    """Test retrieving all pending confirmations across sessions."""
    session_id = setup_test_data['session_id']
    existing_txn_id = setup_test_data['existing_txn_id']

    # Create 2 pending confirmations
    for i in range(2):
        dup_conf_repo.create_confirmation(
            session_id=session_id,
            new_transaction_data='{}',
            new_transaction_index=i,
            existing_transaction_id=existing_txn_id,
            confidence_score=80,
            match_fields='[]',
            difference_summary='Test'
        )

    # Confirm one
    confirmations = dup_conf_repo.get_by_session(session_id)
    dup_conf_repo.apply_user_decision(confirmations[0]['id'], 'skip', 'test_user@example.com')

    # Get all pending
    all_pending = dup_conf_repo.get_all_pending()
    assert len(all_pending) == 1
    assert all_pending[0]['status'] == 'pending'
    # Verify joined fields
    assert all_pending[0]['parser_type'] == 'TEST'
    assert all_pending[0]['file_name'] == 'test_statement.xls'


def test_bulk_confirm_session_skip(dup_conf_repo, setup_test_data, test_db):
    """Test bulk skip all confirmations in a session."""
    session_id = setup_test_data['session_id']
    existing_txn_id = setup_test_data['existing_txn_id']

    # Create 3 pending confirmations
    for i in range(3):
        dup_conf_repo.create_confirmation(
            session_id=session_id,
            new_transaction_data='{}',
            new_transaction_index=i,
            existing_transaction_id=existing_txn_id,
            confidence_score=80,
            match_fields='[]',
            difference_summary='Test'
        )

    # Bulk skip
    count = dup_conf_repo.bulk_confirm_session(
        session_id,
        'skip',
        'test_user@example.com'
    )

    assert count == 3

    # Verify all are confirmed_skip
    confirmations = dup_conf_repo.get_by_session(session_id)
    for conf in confirmations:
        assert conf['status'] == 'confirmed_skip'
        assert conf['user_action'] == 'skip'
        assert conf['user_id'] == 'test_user@example.com'


def test_bulk_confirm_session_insert(dup_conf_repo, setup_test_data, test_db):
    """Test bulk insert all confirmations in a session."""
    session_id = setup_test_data['session_id']
    existing_txn_id = setup_test_data['existing_txn_id']

    # Create 2 pending confirmations with valid transaction data
    for i in range(2):
        new_txn_data = json.dumps({
            'month': '09',
            'date': f'2025.09.{14 + i}',
            'category': 'Test식비',
            'item': f'Test매장{i}',
            'amount': 6000 + i * 1000,
            'source': 'Test카드'
        })

        dup_conf_repo.create_confirmation(
            session_id=session_id,
            new_transaction_data=new_txn_data,
            new_transaction_index=i,
            existing_transaction_id=existing_txn_id,
            confidence_score=70,
            match_fields='[]',
            difference_summary='Test'
        )

    # Count transactions before
    cursor = test_db.execute('SELECT COUNT(*) as count FROM transactions')
    before_count = cursor.fetchone()['count']

    # Bulk insert
    count = dup_conf_repo.bulk_confirm_session(
        session_id,
        'insert',
        'test_user@example.com'
    )

    assert count == 2

    # Verify all are confirmed_insert
    confirmations = dup_conf_repo.get_by_session(session_id)
    for conf in confirmations:
        assert conf['status'] == 'confirmed_insert'

    # Verify transactions were inserted
    cursor = test_db.execute('SELECT COUNT(*) as count FROM transactions')
    after_count = cursor.fetchone()['count']
    assert after_count == before_count + 2


def test_bulk_confirm_session_empty(dup_conf_repo, setup_test_data):
    """Test bulk confirm on session with no pending confirmations."""
    session_id = setup_test_data['session_id']

    count = dup_conf_repo.bulk_confirm_session(
        session_id,
        'skip',
        'test_user@example.com'
    )

    assert count == 0


def test_bulk_confirm_session_invalid_action(dup_conf_repo, setup_test_data):
    """Test that bulk confirm with invalid action raises ValueError."""
    session_id = setup_test_data['session_id']

    with pytest.raises(ValueError, match="Invalid action"):
        dup_conf_repo.bulk_confirm_session(
            session_id,
            'invalid',
            'test_user@example.com'
        )


def test_transaction_insertion_with_installments(dup_conf_repo, setup_test_data, test_db):
    """Test that insert decision handles installment transactions correctly."""
    session_id = setup_test_data['session_id']
    existing_txn_id = setup_test_data['existing_txn_id']

    new_txn_data = json.dumps({
        'month': '09',
        'date': '2025.09.15',
        'category': 'Test식비',
        'item': 'Test할부매장',
        'amount': 10000,
        'source': 'Test카드',
        'installment_months': 3,
        'installment_current': 1,
        'original_amount': 30000
    })

    confirmation_id = dup_conf_repo.create_confirmation(
        session_id=session_id,
        new_transaction_data=new_txn_data,
        new_transaction_index=1,
        existing_transaction_id=existing_txn_id,
        confidence_score=60,
        match_fields='[]',
        difference_summary='Test'
    )

    # Apply insert decision
    dup_conf_repo.apply_user_decision(
        confirmation_id,
        'insert',
        'test_user@example.com'
    )

    # Verify installment fields were saved
    cursor = test_db.execute('''
        SELECT * FROM transactions
        WHERE merchant_name = 'Test할부매장'
    ''')
    txn = cursor.fetchone()
    assert txn is not None
    assert txn['amount'] == 10000
    assert txn['installment_months'] == 3
    assert txn['installment_current'] == 1
    assert txn['original_amount'] == 30000
