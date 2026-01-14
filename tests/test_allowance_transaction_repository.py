"""
Comprehensive unit tests for AllowanceTransactionRepository.

Tests cover:
- Mark/unmark allowance (CRUD operations)
- Duplicate marking prevention (UNIQUE constraint)
- Privacy enforcement (user A marks, user B cannot see)
- Allowance retrieval with filters
- Summary calculations (total amount, count, by category)
- Edge cases (non-existent transactions, deleted transactions)
"""

import sqlite3
import pytest
from datetime import datetime
from src.db.connection import DatabaseConnection
from src.db.repository import (
    AllowanceTransactionRepository,
    TransactionRepository,
    CategoryRepository,
    InstitutionRepository,
    UserRepository,
    WorkspaceRepository,
    WorkspaceMembershipRepository
)
from src.models import Transaction


@pytest.fixture
def setup_test_data(test_db_override):
    """
    Setup test data with users, workspaces, categories, institutions, and transactions.

    Returns:
        dict with keys:
        - user1_id, user2_id, user3_id
        - workspace1_id, workspace2_id
        - category_food_id, category_transport_id, category_util_id
        - institution1_id, institution2_id
        - transaction1_id, transaction2_id, transaction3_id, transaction4_id
    """
    db = DatabaseConnection.get_instance()

    # Create users
    user_repo = UserRepository(db)
    user1_id = user_repo.create_user(
        email='allowance_user1@test.com',
        google_id='google_allowance_1',
        name='Allowance User 1'
    )
    user2_id = user_repo.create_user(
        email='allowance_user2@test.com',
        google_id='google_allowance_2',
        name='Allowance User 2'
    )
    user3_id = user_repo.create_user(
        email='allowance_user3@test.com',
        google_id='google_allowance_3',
        name='Allowance User 3'
    )

    # Create workspaces
    workspace_repo = WorkspaceRepository(db)
    workspace1_id = workspace_repo.create(
        name='Allowance Workspace 1',
        description='Test workspace 1',
        created_by_user_id=user1_id
    )
    workspace2_id = workspace_repo.create(
        name='Allowance Workspace 2',
        description='Test workspace 2',
        created_by_user_id=user2_id
    )

    # Add user2 to workspace1 (for privacy tests)
    membership_repo = WorkspaceMembershipRepository(db)
    membership_repo.add_member(
        workspace_id=workspace1_id,
        user_id=user2_id,
        role='MEMBER_WRITE'
    )

    # Create categories
    cat_repo = CategoryRepository(db)
    category_food_id = cat_repo.get_or_create('식비')
    category_transport_id = cat_repo.get_or_create('교통')
    category_util_id = cat_repo.get_or_create('통신')

    # Create institutions
    inst_repo = InstitutionRepository(db)
    institution1_id = inst_repo.get_or_create('신한카드')
    institution2_id = inst_repo.get_or_create('토스뱅크')

    # Create transactions using TransactionRepository.insert() and manually set workspace_id
    txn_repo = TransactionRepository(db, cat_repo, inst_repo)

    # Transaction 1: 2024-01-15, 식비, 신한카드, workspace1
    transaction1 = Transaction(
        month='01',
        date='2024.01.15',
        category='식비',
        item='맥도날드',
        amount=8500,
        source='신한카드'
    )
    transaction1_id = txn_repo.insert(transaction1)
    db.execute('UPDATE transactions SET workspace_id = ? WHERE id = ?', (workspace1_id, transaction1_id))

    # Transaction 2: 2024-01-20, 교통, 토스뱅크, workspace1
    transaction2 = Transaction(
        month='01',
        date='2024.01.20',
        category='교통',
        item='이마트',
        amount=45000,
        source='토스뱅크'
    )
    transaction2_id = txn_repo.insert(transaction2)
    db.execute('UPDATE transactions SET workspace_id = ? WHERE id = ?', (workspace1_id, transaction2_id))

    # Transaction 3: 2024-02-10, 통신, 신한카드, workspace1
    transaction3 = Transaction(
        month='02',
        date='2024.02.10',
        category='통신',
        item='KT',
        amount=55000,
        source='신한카드'
    )
    transaction3_id = txn_repo.insert(transaction3)
    db.execute('UPDATE transactions SET workspace_id = ? WHERE id = ?', (workspace1_id, transaction3_id))

    # Transaction 4: 2024-01-25, 식비, 신한카드, workspace2
    transaction4 = Transaction(
        month='01',
        date='2024.01.25',
        category='식비',
        item='스타벅스',
        amount=6000,
        source='신한카드'
    )
    transaction4_id = txn_repo.insert(transaction4)
    db.execute('UPDATE transactions SET workspace_id = ? WHERE id = ?', (workspace2_id, transaction4_id))

    db.commit()

    return {
        'user1_id': user1_id,
        'user2_id': user2_id,
        'user3_id': user3_id,
        'workspace1_id': workspace1_id,
        'workspace2_id': workspace2_id,
        'category_food_id': category_food_id,
        'category_transport_id': category_transport_id,
        'category_util_id': category_util_id,
        'institution1_id': institution1_id,
        'institution2_id': institution2_id,
        'transaction1_id': transaction1_id,
        'transaction2_id': transaction2_id,
        'transaction3_id': transaction3_id,
        'transaction4_id': transaction4_id,
    }


# ===============================
# Test: Mark as Allowance
# ===============================

def test_mark_as_allowance_success(setup_test_data):
    """Test successfully marking a transaction as allowance."""
    data = setup_test_data
    db = DatabaseConnection.get_instance()
    repo = AllowanceTransactionRepository(db)

    allowance_id = repo.mark_as_allowance(
        db=db,
        transaction_id=data['transaction1_id'],
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id'],
        notes='Personal lunch expense'
    )

    assert allowance_id > 0

    # Verify marking exists
    cursor = db.execute(
        'SELECT * FROM allowance_transactions WHERE id = ?',
        (allowance_id,)
    )
    row = cursor.fetchone()
    assert row is not None
    assert row['transaction_id'] == data['transaction1_id']
    assert row['user_id'] == data['user1_id']
    assert row['workspace_id'] == data['workspace1_id']
    assert row['notes'] == 'Personal lunch expense'
    assert row['marked_at'] is not None


def test_mark_as_allowance_without_notes(setup_test_data):
    """Test marking as allowance without notes."""
    data = setup_test_data
    db = DatabaseConnection.get_instance()
    repo = AllowanceTransactionRepository(db)

    allowance_id = repo.mark_as_allowance(
        db=db,
        transaction_id=data['transaction1_id'],
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )

    assert allowance_id > 0

    cursor = db.execute(
        'SELECT notes FROM allowance_transactions WHERE id = ?',
        (allowance_id,)
    )
    row = cursor.fetchone()
    assert row['notes'] is None


def test_mark_as_allowance_duplicate_constraint(setup_test_data):
    """Test UNIQUE constraint prevents duplicate markings."""
    data = setup_test_data
    db = DatabaseConnection.get_instance()
    repo = AllowanceTransactionRepository(db)

    # First marking succeeds
    repo.mark_as_allowance(
        db=db,
        transaction_id=data['transaction1_id'],
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )

    # Second marking should raise IntegrityError
    with pytest.raises(sqlite3.IntegrityError):
        repo.mark_as_allowance(
            db=db,
            transaction_id=data['transaction1_id'],
            user_id=data['user1_id'],
            workspace_id=data['workspace1_id']
        )


def test_mark_as_allowance_invalid_transaction_id(setup_test_data):
    """Test marking with non-existent transaction_id raises IntegrityError."""
    data = setup_test_data
    db = DatabaseConnection.get_instance()
    repo = AllowanceTransactionRepository(db)

    with pytest.raises(sqlite3.IntegrityError):
        repo.mark_as_allowance(
            db=db,
            transaction_id=99999,  # Non-existent
            user_id=data['user1_id'],
            workspace_id=data['workspace1_id']
        )


def test_mark_as_allowance_invalid_user_id(setup_test_data):
    """Test marking with non-existent user_id raises IntegrityError."""
    data = setup_test_data
    db = DatabaseConnection.get_instance()
    repo = AllowanceTransactionRepository(db)

    with pytest.raises(sqlite3.IntegrityError):
        repo.mark_as_allowance(
            db=db,
            transaction_id=data['transaction1_id'],
            user_id=99999,  # Non-existent
            workspace_id=data['workspace1_id']
        )


def test_mark_as_allowance_invalid_workspace_id(setup_test_data):
    """Test marking with non-existent workspace_id raises IntegrityError."""
    data = setup_test_data
    db = DatabaseConnection.get_instance()
    repo = AllowanceTransactionRepository(db)

    with pytest.raises(sqlite3.IntegrityError):
        repo.mark_as_allowance(
            db=db,
            transaction_id=data['transaction1_id'],
            user_id=data['user1_id'],
            workspace_id=99999  # Non-existent
        )


# ===============================
# Test: Unmark Allowance
# ===============================

def test_unmark_allowance_success(setup_test_data):
    """Test successfully unmarking an allowance."""
    data = setup_test_data
    db = DatabaseConnection.get_instance()
    repo = AllowanceTransactionRepository(db)

    # Mark first
    allowance_id = repo.mark_as_allowance(
        db=db,
        transaction_id=data['transaction1_id'],
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )

    # Unmark
    success = repo.unmark_allowance(
        db=db,
        transaction_id=data['transaction1_id'],
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )

    assert success is True

    # Verify marking deleted
    cursor = db.execute(
        'SELECT * FROM allowance_transactions WHERE id = ?',
        (allowance_id,)
    )
    row = cursor.fetchone()
    assert row is None


def test_unmark_allowance_not_found(setup_test_data):
    """Test unmarking non-existent allowance returns False."""
    data = setup_test_data
    db = DatabaseConnection.get_instance()
    repo = AllowanceTransactionRepository(db)

    success = repo.unmark_allowance(
        db=db,
        transaction_id=data['transaction1_id'],
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )

    assert success is False


def test_unmark_allowance_wrong_user(setup_test_data):
    """Test unmarking with wrong user_id returns False (privacy)."""
    data = setup_test_data
    db = DatabaseConnection.get_instance()
    repo = AllowanceTransactionRepository(db)

    # User1 marks
    repo.mark_as_allowance(
        db=db,
        transaction_id=data['transaction1_id'],
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )

    # User2 tries to unmark (should fail)
    success = repo.unmark_allowance(
        db=db,
        transaction_id=data['transaction1_id'],
        user_id=data['user2_id'],  # Different user
        workspace_id=data['workspace1_id']
    )

    assert success is False

    # Verify marking still exists for user1
    is_marked = repo.is_allowance(
        db=db,
        transaction_id=data['transaction1_id'],
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )
    assert is_marked is True


# ===============================
# Test: Privacy Enforcement
# ===============================

def test_privacy_user_a_marks_user_b_cannot_see(setup_test_data):
    """CRITICAL: Verify allowance privacy - user A marks, user B cannot see it."""
    data = setup_test_data
    db = DatabaseConnection.get_instance()
    repo = AllowanceTransactionRepository(db)

    # User1 marks transaction as allowance
    repo.mark_as_allowance(
        db=db,
        transaction_id=data['transaction1_id'],
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )

    # User1 can see it
    user1_allowances, count1 = repo.get_user_allowances(
        db=db,
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )
    assert count1 == 1
    assert user1_allowances[0]['id'] == data['transaction1_id']

    # User2 CANNOT see it (different user_id, same workspace)
    user2_allowances, count2 = repo.get_user_allowances(
        db=db,
        user_id=data['user2_id'],
        workspace_id=data['workspace1_id']
    )
    assert count2 == 0  # CRITICAL: Privacy enforcement


def test_privacy_multiple_users_same_workspace(setup_test_data):
    """Test multiple users marking different transactions in same workspace."""
    data = setup_test_data
    db = DatabaseConnection.get_instance()
    repo = AllowanceTransactionRepository(db)

    # User1 marks transaction1
    repo.mark_as_allowance(
        db=db,
        transaction_id=data['transaction1_id'],
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )

    # User2 marks transaction2
    repo.mark_as_allowance(
        db=db,
        transaction_id=data['transaction2_id'],
        user_id=data['user2_id'],
        workspace_id=data['workspace1_id']
    )

    # User1 sees only transaction1
    user1_allowances, count1 = repo.get_user_allowances(
        db=db,
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )
    assert count1 == 1
    assert user1_allowances[0]['id'] == data['transaction1_id']

    # User2 sees only transaction2
    user2_allowances, count2 = repo.get_user_allowances(
        db=db,
        user_id=data['user2_id'],
        workspace_id=data['workspace1_id']
    )
    assert count2 == 1
    assert user2_allowances[0]['id'] == data['transaction2_id']


# ===============================
# Test: Get User Allowances
# ===============================

def test_get_user_allowances_empty(setup_test_data):
    """Test get_user_allowances returns empty list when no allowances."""
    data = setup_test_data
    db = DatabaseConnection.get_instance()
    repo = AllowanceTransactionRepository(db)

    allowances, count = repo.get_user_allowances(
        db=db,
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )

    assert allowances == []
    assert count == 0


def test_get_user_allowances_multiple(setup_test_data):
    """Test retrieving multiple allowances."""
    data = setup_test_data
    db = DatabaseConnection.get_instance()
    repo = AllowanceTransactionRepository(db)

    # Mark 3 transactions
    repo.mark_as_allowance(
        db=db,
        transaction_id=data['transaction1_id'],
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )
    repo.mark_as_allowance(
        db=db,
        transaction_id=data['transaction2_id'],
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )
    repo.mark_as_allowance(
        db=db,
        transaction_id=data['transaction3_id'],
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )

    allowances, count = repo.get_user_allowances(
        db=db,
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )

    assert count == 3
    assert len(allowances) == 3

    # Verify ordered by transaction_date DESC
    assert allowances[0]['transaction_date'] == '2024-02-10'  # transaction3 (newest)
    assert allowances[1]['transaction_date'] == '2024-01-20'  # transaction2
    assert allowances[2]['transaction_date'] == '2024-01-15'  # transaction1 (oldest)


def test_get_user_allowances_includes_joined_fields(setup_test_data):
    """Test that allowances include category_name, institution_name, marked_at, allowance_notes."""
    data = setup_test_data
    db = DatabaseConnection.get_instance()
    repo = AllowanceTransactionRepository(db)

    repo.mark_as_allowance(
        db=db,
        transaction_id=data['transaction1_id'],
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id'],
        notes='Test note'
    )

    allowances, count = repo.get_user_allowances(
        db=db,
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )

    assert count == 1
    txn = allowances[0]

    # Check joined fields
    assert txn['category_name'] == '식비'
    assert txn['institution_name'] == '신한카드'
    assert txn['marked_at'] is not None
    assert txn['allowance_notes'] == 'Test note'


# ===============================
# Test: Filters
# ===============================

def test_get_user_allowances_filter_by_year(setup_test_data):
    """Test filtering allowances by year."""
    data = setup_test_data
    db = DatabaseConnection.get_instance()
    repo = AllowanceTransactionRepository(db)

    # Mark transactions from 2024-01 and 2024-02
    repo.mark_as_allowance(
        db=db,
        transaction_id=data['transaction1_id'],  # 2024-01-15
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )
    repo.mark_as_allowance(
        db=db,
        transaction_id=data['transaction3_id'],  # 2024-02-10
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )

    # Filter by year 2024
    allowances, count = repo.get_user_allowances(
        db=db,
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id'],
        filters={'year': 2024}
    )

    assert count == 2


def test_get_user_allowances_filter_by_month(setup_test_data):
    """Test filtering allowances by month."""
    data = setup_test_data
    db = DatabaseConnection.get_instance()
    repo = AllowanceTransactionRepository(db)

    # Mark transactions from different months
    repo.mark_as_allowance(
        db=db,
        transaction_id=data['transaction1_id'],  # 2024-01-15
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )
    repo.mark_as_allowance(
        db=db,
        transaction_id=data['transaction2_id'],  # 2024-01-20
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )
    repo.mark_as_allowance(
        db=db,
        transaction_id=data['transaction3_id'],  # 2024-02-10
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )

    # Filter by January (month=1)
    allowances, count = repo.get_user_allowances(
        db=db,
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id'],
        filters={'month': 1}
    )

    assert count == 2
    for txn in allowances:
        assert txn['transaction_month'] == 1


def test_get_user_allowances_filter_by_year_and_month(setup_test_data):
    """Test filtering allowances by year and month combined."""
    data = setup_test_data
    db = DatabaseConnection.get_instance()
    repo = AllowanceTransactionRepository(db)

    repo.mark_as_allowance(
        db=db,
        transaction_id=data['transaction1_id'],  # 2024-01-15
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )

    allowances, count = repo.get_user_allowances(
        db=db,
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id'],
        filters={'year': 2024, 'month': 1}
    )

    assert count == 1


def test_get_user_allowances_filter_by_category(setup_test_data):
    """Test filtering allowances by category."""
    data = setup_test_data
    db = DatabaseConnection.get_instance()
    repo = AllowanceTransactionRepository(db)

    # Mark transactions with different categories
    repo.mark_as_allowance(
        db=db,
        transaction_id=data['transaction1_id'],  # 식비
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )
    repo.mark_as_allowance(
        db=db,
        transaction_id=data['transaction2_id'],  # 교통
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )

    # Filter by 식비 category
    allowances, count = repo.get_user_allowances(
        db=db,
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id'],
        filters={'category_id': data['category_food_id']}
    )

    assert count == 1
    assert allowances[0]['category_name'] == '식비'


def test_get_user_allowances_filter_by_institution(setup_test_data):
    """Test filtering allowances by financial institution."""
    data = setup_test_data
    db = DatabaseConnection.get_instance()
    repo = AllowanceTransactionRepository(db)

    # Mark transactions with different institutions
    repo.mark_as_allowance(
        db=db,
        transaction_id=data['transaction1_id'],  # 신한카드
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )
    repo.mark_as_allowance(
        db=db,
        transaction_id=data['transaction2_id'],  # 토스뱅크
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )

    # Filter by 신한카드
    allowances, count = repo.get_user_allowances(
        db=db,
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id'],
        filters={'institution_id': data['institution1_id']}
    )

    assert count == 1
    assert allowances[0]['institution_name'] == '신한카드'


def test_get_user_allowances_filter_by_search(setup_test_data):
    """Test filtering allowances by merchant name search."""
    data = setup_test_data
    db = DatabaseConnection.get_instance()
    repo = AllowanceTransactionRepository(db)

    # Mark transactions with different merchant names
    repo.mark_as_allowance(
        db=db,
        transaction_id=data['transaction1_id'],  # 맥도날드
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )
    repo.mark_as_allowance(
        db=db,
        transaction_id=data['transaction2_id'],  # 이마트
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )

    # Search for "맥도"
    allowances, count = repo.get_user_allowances(
        db=db,
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id'],
        filters={'search': '맥도'}
    )

    assert count == 1
    assert '맥도날드' in allowances[0]['merchant_name']


def test_get_user_allowances_filter_multiple_combined(setup_test_data):
    """Test combining multiple filters."""
    data = setup_test_data
    db = DatabaseConnection.get_instance()
    repo = AllowanceTransactionRepository(db)

    repo.mark_as_allowance(
        db=db,
        transaction_id=data['transaction1_id'],  # 2024-01-15, 식비, 신한카드, 맥도날드
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )
    repo.mark_as_allowance(
        db=db,
        transaction_id=data['transaction2_id'],  # 2024-01-20, 교통, 토스뱅크, 이마트
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )

    # Filter: year=2024, month=1, category=식비
    allowances, count = repo.get_user_allowances(
        db=db,
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id'],
        filters={
            'year': 2024,
            'month': 1,
            'category_id': data['category_food_id']
        }
    )

    assert count == 1
    assert allowances[0]['merchant_name'] == '맥도날드'


# ===============================
# Test: Soft-Deleted Transactions
# ===============================

def test_get_user_allowances_excludes_deleted_transactions(setup_test_data):
    """Test that soft-deleted transactions are excluded from allowances."""
    data = setup_test_data
    db = DatabaseConnection.get_instance()
    repo = AllowanceTransactionRepository(db)
    cat_repo = CategoryRepository(db)
    inst_repo = InstitutionRepository(db)
    txn_repo = TransactionRepository(db, cat_repo, inst_repo)

    # Mark transaction as allowance
    repo.mark_as_allowance(
        db=db,
        transaction_id=data['transaction1_id'],
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )

    # Verify it appears
    allowances, count = repo.get_user_allowances(
        db=db,
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )
    assert count == 1

    # Soft-delete transaction
    txn_repo.soft_delete(transaction_id=data['transaction1_id'], validate_editable=False)

    # Verify it no longer appears
    allowances, count = repo.get_user_allowances(
        db=db,
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )
    assert count == 0


# ===============================
# Test: Get Allowance Summary
# ===============================

def test_get_allowance_summary_empty(setup_test_data):
    """Test summary returns zeros when no allowances exist."""
    data = setup_test_data
    db = DatabaseConnection.get_instance()
    repo = AllowanceTransactionRepository(db)

    summary = repo.get_allowance_summary(
        db=db,
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id'],
        year=2024,
        month=1
    )

    assert summary['total_amount'] == 0
    assert summary['transaction_count'] == 0
    assert summary['by_category'] == []


def test_get_allowance_summary_single_transaction(setup_test_data):
    """Test summary with single transaction."""
    data = setup_test_data
    db = DatabaseConnection.get_instance()
    repo = AllowanceTransactionRepository(db)

    repo.mark_as_allowance(
        db=db,
        transaction_id=data['transaction1_id'],  # 8500원, 2024-01-15, 식비
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )

    summary = repo.get_allowance_summary(
        db=db,
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id'],
        year=2024,
        month=1
    )

    assert summary['total_amount'] == 8500
    assert summary['transaction_count'] == 1
    assert len(summary['by_category']) == 1
    assert summary['by_category'][0]['category_name'] == '식비'
    assert summary['by_category'][0]['amount'] == 8500
    assert summary['by_category'][0]['count'] == 1


def test_get_allowance_summary_multiple_transactions_multiple_categories(setup_test_data):
    """Test summary with multiple transactions across multiple categories."""
    data = setup_test_data
    db = DatabaseConnection.get_instance()
    repo = AllowanceTransactionRepository(db)

    # Mark 2 transactions in January 2024
    repo.mark_as_allowance(
        db=db,
        transaction_id=data['transaction1_id'],  # 8500원, 식비
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )
    repo.mark_as_allowance(
        db=db,
        transaction_id=data['transaction2_id'],  # 45000원, 교통
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )

    summary = repo.get_allowance_summary(
        db=db,
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id'],
        year=2024,
        month=1
    )

    assert summary['total_amount'] == 53500  # 8500 + 45000
    assert summary['transaction_count'] == 2
    assert len(summary['by_category']) == 2

    # Verify ordered by amount DESC (교통 45000 > 식비 8500)
    assert summary['by_category'][0]['category_name'] == '교통'
    assert summary['by_category'][0]['amount'] == 45000
    assert summary['by_category'][0]['count'] == 1

    assert summary['by_category'][1]['category_name'] == '식비'
    assert summary['by_category'][1]['amount'] == 8500
    assert summary['by_category'][1]['count'] == 1


def test_get_allowance_summary_filters_by_month(setup_test_data):
    """Test summary correctly filters by month."""
    data = setup_test_data
    db = DatabaseConnection.get_instance()
    repo = AllowanceTransactionRepository(db)

    # Mark transactions in different months
    repo.mark_as_allowance(
        db=db,
        transaction_id=data['transaction1_id'],  # January
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )
    repo.mark_as_allowance(
        db=db,
        transaction_id=data['transaction3_id'],  # February
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )

    # Get January summary
    summary_jan = repo.get_allowance_summary(
        db=db,
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id'],
        year=2024,
        month=1
    )
    assert summary_jan['transaction_count'] == 1
    assert summary_jan['total_amount'] == 8500

    # Get February summary
    summary_feb = repo.get_allowance_summary(
        db=db,
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id'],
        year=2024,
        month=2
    )
    assert summary_feb['transaction_count'] == 1
    assert summary_feb['total_amount'] == 55000


def test_get_allowance_summary_excludes_deleted_transactions(setup_test_data):
    """Test summary excludes soft-deleted transactions."""
    data = setup_test_data
    db = DatabaseConnection.get_instance()
    repo = AllowanceTransactionRepository(db)
    cat_repo = CategoryRepository(db)
    inst_repo = InstitutionRepository(db)
    txn_repo = TransactionRepository(db, cat_repo, inst_repo)

    # Mark transaction
    repo.mark_as_allowance(
        db=db,
        transaction_id=data['transaction1_id'],
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )

    # Verify appears in summary
    summary = repo.get_allowance_summary(
        db=db,
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id'],
        year=2024,
        month=1
    )
    assert summary['transaction_count'] == 1

    # Soft-delete transaction
    txn_repo.soft_delete(transaction_id=data['transaction1_id'], validate_editable=False)

    # Verify excluded from summary
    summary = repo.get_allowance_summary(
        db=db,
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id'],
        year=2024,
        month=1
    )
    assert summary['transaction_count'] == 0
    assert summary['total_amount'] == 0


def test_get_allowance_summary_privacy_enforcement(setup_test_data):
    """Test summary only includes specific user's allowances."""
    data = setup_test_data
    db = DatabaseConnection.get_instance()
    repo = AllowanceTransactionRepository(db)

    # User1 marks transaction1
    repo.mark_as_allowance(
        db=db,
        transaction_id=data['transaction1_id'],
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )

    # User2 marks transaction2
    repo.mark_as_allowance(
        db=db,
        transaction_id=data['transaction2_id'],
        user_id=data['user2_id'],
        workspace_id=data['workspace1_id']
    )

    # User1 summary only includes transaction1
    summary1 = repo.get_allowance_summary(
        db=db,
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id'],
        year=2024,
        month=1
    )
    assert summary1['transaction_count'] == 1
    assert summary1['total_amount'] == 8500

    # User2 summary only includes transaction2
    summary2 = repo.get_allowance_summary(
        db=db,
        user_id=data['user2_id'],
        workspace_id=data['workspace1_id'],
        year=2024,
        month=1
    )
    assert summary2['transaction_count'] == 1
    assert summary2['total_amount'] == 45000


# ===============================
# Test: Is Allowance
# ===============================

def test_is_allowance_true(setup_test_data):
    """Test is_allowance returns True for marked transactions."""
    data = setup_test_data
    db = DatabaseConnection.get_instance()
    repo = AllowanceTransactionRepository(db)

    repo.mark_as_allowance(
        db=db,
        transaction_id=data['transaction1_id'],
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )

    is_marked = repo.is_allowance(
        db=db,
        transaction_id=data['transaction1_id'],
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )

    assert is_marked is True


def test_is_allowance_false(setup_test_data):
    """Test is_allowance returns False for unmarked transactions."""
    data = setup_test_data
    db = DatabaseConnection.get_instance()
    repo = AllowanceTransactionRepository(db)

    is_marked = repo.is_allowance(
        db=db,
        transaction_id=data['transaction1_id'],
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )

    assert is_marked is False


def test_is_allowance_privacy_enforcement(setup_test_data):
    """Test is_allowance enforces privacy (user-specific)."""
    data = setup_test_data
    db = DatabaseConnection.get_instance()
    repo = AllowanceTransactionRepository(db)

    # User1 marks
    repo.mark_as_allowance(
        db=db,
        transaction_id=data['transaction1_id'],
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )

    # User1 sees it as marked
    is_marked_user1 = repo.is_allowance(
        db=db,
        transaction_id=data['transaction1_id'],
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )
    assert is_marked_user1 is True

    # User2 sees it as NOT marked
    is_marked_user2 = repo.is_allowance(
        db=db,
        transaction_id=data['transaction1_id'],
        user_id=data['user2_id'],
        workspace_id=data['workspace1_id']
    )
    assert is_marked_user2 is False


# ===============================
# Test: Edge Cases
# ===============================

def test_cascade_delete_on_transaction_deletion(setup_test_data):
    """Test that deleting transaction cascades to allowance_transactions."""
    data = setup_test_data
    db = DatabaseConnection.get_instance()
    repo = AllowanceTransactionRepository(db)

    # Mark transaction
    allowance_id = repo.mark_as_allowance(
        db=db,
        transaction_id=data['transaction1_id'],
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )

    # Hard delete transaction (not soft delete)
    db.execute('DELETE FROM transactions WHERE id = ?', (data['transaction1_id'],))
    db.commit()

    # Verify allowance marking also deleted (CASCADE)
    cursor = db.execute(
        'SELECT * FROM allowance_transactions WHERE id = ?',
        (allowance_id,)
    )
    row = cursor.fetchone()
    assert row is None


def test_cascade_delete_on_user_deletion(setup_test_data):
    """Test that deleting user cascades to allowance_transactions."""
    data = setup_test_data
    db = DatabaseConnection.get_instance()
    repo = AllowanceTransactionRepository(db)

    # Mark transaction
    allowance_id = repo.mark_as_allowance(
        db=db,
        transaction_id=data['transaction1_id'],
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )

    # Delete workspace first (user1 created it, so it has FK constraint)
    db.execute('DELETE FROM workspaces WHERE id = ?', (data['workspace1_id'],))
    # Delete user
    db.execute('DELETE FROM users WHERE id = ?', (data['user1_id'],))
    db.commit()

    # Verify allowance marking also deleted (CASCADE)
    cursor = db.execute(
        'SELECT * FROM allowance_transactions WHERE id = ?',
        (allowance_id,)
    )
    row = cursor.fetchone()
    assert row is None


def test_cascade_delete_on_workspace_deletion(setup_test_data):
    """Test that deleting workspace cascades to allowance_transactions."""
    data = setup_test_data
    db = DatabaseConnection.get_instance()
    repo = AllowanceTransactionRepository(db)

    # Mark transaction
    allowance_id = repo.mark_as_allowance(
        db=db,
        transaction_id=data['transaction1_id'],
        user_id=data['user1_id'],
        workspace_id=data['workspace1_id']
    )

    # Delete workspace
    db.execute('DELETE FROM workspaces WHERE id = ?', (data['workspace1_id'],))
    db.commit()

    # Verify allowance marking also deleted (CASCADE)
    cursor = db.execute(
        'SELECT * FROM allowance_transactions WHERE id = ?',
        (allowance_id,)
    )
    row = cursor.fetchone()
    assert row is None
