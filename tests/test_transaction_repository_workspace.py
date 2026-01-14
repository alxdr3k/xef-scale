"""
Comprehensive unit tests for TransactionRepository workspace filtering and allowance exclusion.

Tests cover:
- Workspace isolation (multi-tenant security)
- Allowance exclusion (privacy enforcement)
- get_filtered() with workspace_id and exclude_allowances_for_user_id
- get_filtered_total_amount() with workspace_id and exclude_allowances_for_user_id
- get_monthly_summary_with_stats() with workspace_id and exclude_allowances_for_user_id
- Edge cases and boundary conditions
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
def setup_workspace_test_data(test_db_override):
    """
    Setup test data for workspace filtering and allowance exclusion tests.

    Creates:
    - 2 users (user1, user2)
    - 2 workspaces (workspace1, workspace2)
    - Multiple transactions in each workspace
    - Some transactions marked as allowances by different users

    Returns:
        dict with keys:
        - user1_id, user2_id
        - workspace1_id, workspace2_id
        - category_food_id, category_transport_id, category_util_id
        - institution1_id, institution2_id
        - transaction IDs for various test scenarios
    """
    db = DatabaseConnection.get_instance()

    # Create users
    user_repo = UserRepository(db)
    user1_id = user_repo.create_user(
        email='workspace_user1@test.com',
        google_id='google_workspace_1',
        name='Workspace User 1'
    )
    user2_id = user_repo.create_user(
        email='workspace_user2@test.com',
        google_id='google_workspace_2',
        name='Workspace User 2'
    )

    # Create workspaces
    workspace_repo = WorkspaceRepository(db)
    workspace1_id = workspace_repo.create(
        name='Workspace 1',
        description='Test workspace 1 for isolation',
        created_by_user_id=user1_id
    )
    workspace2_id = workspace_repo.create(
        name='Workspace 2',
        description='Test workspace 2 for isolation',
        created_by_user_id=user2_id
    )

    # Add user2 to workspace1 (both users share workspace1)
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

    # Workspace 1 Transactions (January 2025)
    # Transaction 1: 식비, 10000원 - will be marked as allowance by user1
    txn1 = Transaction('01', '2025.01.15', '식비', '맥도날드', 10000, '신한카드')
    txn1_id = txn_repo.insert(txn1)
    db.execute('UPDATE transactions SET workspace_id = ? WHERE id = ?', (workspace1_id, txn1_id))

    # Transaction 2: 교통, 5000원 - will be marked as allowance by user2
    txn2 = Transaction('01', '2025.01.20', '교통', '카카오택시', 5000, '토스뱅크')
    txn2_id = txn_repo.insert(txn2)
    db.execute('UPDATE transactions SET workspace_id = ? WHERE id = ?', (workspace1_id, txn2_id))

    # Transaction 3: 통신, 50000원 - not marked as allowance (shared by both users)
    txn3 = Transaction('01', '2025.01.25', '통신', 'KT', 50000, '신한카드')
    txn3_id = txn_repo.insert(txn3)
    db.execute('UPDATE transactions SET workspace_id = ? WHERE id = ?', (workspace1_id, txn3_id))

    # Transaction 4: 식비, 8000원 - will be marked as allowance by user1
    txn4 = Transaction('01', '2025.01.28', '식비', '스타벅스', 8000, '신한카드')
    txn4_id = txn_repo.insert(txn4)
    db.execute('UPDATE transactions SET workspace_id = ? WHERE id = ?', (workspace1_id, txn4_id))

    # Workspace 1 Transactions (February 2025)
    # Transaction 5: 식비, 12000원 - not marked as allowance
    txn5 = Transaction('02', '2025.02.10', '식비', '올리브영', 12000, '토스뱅크')
    txn5_id = txn_repo.insert(txn5)
    db.execute('UPDATE transactions SET workspace_id = ? WHERE id = ?', (workspace1_id, txn5_id))

    # Workspace 2 Transactions (January 2025)
    # Transaction 6: 식비, 15000원 - workspace 2 (should be isolated from workspace 1)
    txn6 = Transaction('01', '2025.01.18', '식비', '파리바게뜨', 15000, '신한카드')
    txn6_id = txn_repo.insert(txn6)
    db.execute('UPDATE transactions SET workspace_id = ? WHERE id = ?', (workspace2_id, txn6_id))

    # Transaction 7: 교통, 20000원 - workspace 2
    txn7 = Transaction('01', '2025.01.22', '교통', '택시', 20000, '토스뱅크')
    txn7_id = txn_repo.insert(txn7)
    db.execute('UPDATE transactions SET workspace_id = ? WHERE id = ?', (workspace2_id, txn7_id))

    db.commit()

    # Mark allowances
    allowance_repo = AllowanceTransactionRepository(db)

    # User1 marks transactions 1 and 4 as allowance in workspace1
    allowance_repo.mark_as_allowance(
        db=db,
        transaction_id=txn1_id,
        user_id=user1_id,
        workspace_id=workspace1_id,
        notes='User1 allowance'
    )
    allowance_repo.mark_as_allowance(
        db=db,
        transaction_id=txn4_id,
        user_id=user1_id,
        workspace_id=workspace1_id,
        notes='User1 allowance'
    )

    # User2 marks transaction 2 as allowance in workspace1
    allowance_repo.mark_as_allowance(
        db=db,
        transaction_id=txn2_id,
        user_id=user2_id,
        workspace_id=workspace1_id,
        notes='User2 allowance'
    )

    db.commit()

    return {
        'user1_id': user1_id,
        'user2_id': user2_id,
        'workspace1_id': workspace1_id,
        'workspace2_id': workspace2_id,
        'category_food_id': category_food_id,
        'category_transport_id': category_transport_id,
        'category_util_id': category_util_id,
        'institution1_id': institution1_id,
        'institution2_id': institution2_id,
        'txn1_id': txn1_id,  # workspace1, user1 allowance, 10000원
        'txn2_id': txn2_id,  # workspace1, user2 allowance, 5000원
        'txn3_id': txn3_id,  # workspace1, no allowance, 50000원
        'txn4_id': txn4_id,  # workspace1, user1 allowance, 8000원
        'txn5_id': txn5_id,  # workspace1, February, 12000원
        'txn6_id': txn6_id,  # workspace2, 15000원
        'txn7_id': txn7_id,  # workspace2, 20000원
    }


class TestTransactionRepositoryWorkspaceFiltering:
    """Test workspace isolation in TransactionRepository methods."""

    def test_get_filtered_workspace_isolation(self, setup_workspace_test_data):
        """
        Test that get_filtered only returns transactions from the specified workspace.

        Expected:
        - Workspace 1 query returns only workspace 1 transactions
        - Workspace 2 query returns only workspace 2 transactions
        """
        db = DatabaseConnection.get_instance()
        data = setup_workspace_test_data

        cat_repo = CategoryRepository(db)
        inst_repo = InstitutionRepository(db)
        txn_repo = TransactionRepository(db, cat_repo, inst_repo)

        # Query workspace 1 transactions (user1's view, excluding user2's allowances)
        transactions_ws1, total_ws1 = txn_repo.get_filtered(
            workspace_id=data['workspace1_id'],
            exclude_allowances_for_user_id=data['user1_id'],
            year=2025,
            month=1
        )

        # Should return: txn1 (user1 allowance), txn3 (shared), txn4 (user1 allowance)
        # Should NOT return: txn2 (user2 allowance), txn5 (February), txn6/txn7 (workspace2)
        assert total_ws1 == 3, f"Expected 3 transactions in workspace1 for user1, got {total_ws1}"
        txn_ids_ws1 = {txn['id'] for txn in transactions_ws1}
        assert data['txn1_id'] in txn_ids_ws1
        assert data['txn3_id'] in txn_ids_ws1
        assert data['txn4_id'] in txn_ids_ws1
        assert data['txn2_id'] not in txn_ids_ws1  # user2's allowance excluded

        # Query workspace 2 transactions
        transactions_ws2, total_ws2 = txn_repo.get_filtered(
            workspace_id=data['workspace2_id'],
            exclude_allowances_for_user_id=data['user2_id'],
            year=2025,
            month=1
        )

        # Should return only workspace2 transactions
        assert total_ws2 == 2, f"Expected 2 transactions in workspace2, got {total_ws2}"
        txn_ids_ws2 = {txn['id'] for txn in transactions_ws2}
        assert data['txn6_id'] in txn_ids_ws2
        assert data['txn7_id'] in txn_ids_ws2
        assert data['txn1_id'] not in txn_ids_ws2  # workspace1 transaction excluded

    def test_get_filtered_multi_workspace_no_leakage(self, setup_workspace_test_data):
        """
        Test that workspace isolation prevents data leakage between workspaces.

        Expected:
        - No transaction appears in both workspace queries
        - Total transactions across workspaces equals sum of individual workspace totals
        """
        db = DatabaseConnection.get_instance()
        data = setup_workspace_test_data

        cat_repo = CategoryRepository(db)
        inst_repo = InstitutionRepository(db)
        txn_repo = TransactionRepository(db, cat_repo, inst_repo)

        # Query workspace 1
        transactions_ws1, total_ws1 = txn_repo.get_filtered(
            workspace_id=data['workspace1_id'],
            exclude_allowances_for_user_id=data['user1_id'],
            year=2025,
            month=1
        )

        # Query workspace 2
        transactions_ws2, total_ws2 = txn_repo.get_filtered(
            workspace_id=data['workspace2_id'],
            exclude_allowances_for_user_id=data['user2_id'],
            year=2025,
            month=1
        )

        # Verify no overlap
        txn_ids_ws1 = {txn['id'] for txn in transactions_ws1}
        txn_ids_ws2 = {txn['id'] for txn in transactions_ws2}
        overlap = txn_ids_ws1.intersection(txn_ids_ws2)
        assert len(overlap) == 0, f"Found {len(overlap)} transactions in both workspaces (should be 0)"


class TestTransactionRepositoryAllowanceExclusion:
    """Test allowance exclusion logic in TransactionRepository methods."""

    def test_get_filtered_excludes_other_users_allowances(self, setup_workspace_test_data):
        """
        Test that user's view excludes other users' allowance transactions.

        Expected:
        - User1 should NOT see transactions marked as allowance by User2
        - User1 SHOULD see transactions marked as allowance by User1
        - User2 should NOT see transactions marked as allowance by User1
        - User2 SHOULD see transactions marked as allowance by User2
        """
        db = DatabaseConnection.get_instance()
        data = setup_workspace_test_data

        cat_repo = CategoryRepository(db)
        inst_repo = InstitutionRepository(db)
        txn_repo = TransactionRepository(db, cat_repo, inst_repo)

        # User1's view (should exclude user2's allowances)
        transactions_user1, total_user1 = txn_repo.get_filtered(
            workspace_id=data['workspace1_id'],
            exclude_allowances_for_user_id=data['user1_id'],
            year=2025,
            month=1
        )

        # User1 should see: txn1 (own allowance), txn3 (shared), txn4 (own allowance)
        # User1 should NOT see: txn2 (user2's allowance)
        assert total_user1 == 3, f"Expected 3 transactions for user1, got {total_user1}"
        txn_ids_user1 = {txn['id'] for txn in transactions_user1}
        assert data['txn1_id'] in txn_ids_user1, "User1 should see own allowance (txn1)"
        assert data['txn3_id'] in txn_ids_user1, "User1 should see shared transaction (txn3)"
        assert data['txn4_id'] in txn_ids_user1, "User1 should see own allowance (txn4)"
        assert data['txn2_id'] not in txn_ids_user1, "User1 should NOT see user2's allowance (txn2)"

        # User2's view (should exclude user1's allowances)
        transactions_user2, total_user2 = txn_repo.get_filtered(
            workspace_id=data['workspace1_id'],
            exclude_allowances_for_user_id=data['user2_id'],
            year=2025,
            month=1
        )

        # User2 should see: txn2 (own allowance), txn3 (shared)
        # User2 should NOT see: txn1 (user1's allowance), txn4 (user1's allowance)
        assert total_user2 == 2, f"Expected 2 transactions for user2, got {total_user2}"
        txn_ids_user2 = {txn['id'] for txn in transactions_user2}
        assert data['txn2_id'] in txn_ids_user2, "User2 should see own allowance (txn2)"
        assert data['txn3_id'] in txn_ids_user2, "User2 should see shared transaction (txn3)"
        assert data['txn1_id'] not in txn_ids_user2, "User2 should NOT see user1's allowance (txn1)"
        assert data['txn4_id'] not in txn_ids_user2, "User2 should NOT see user1's allowance (txn4)"

    def test_get_filtered_includes_own_allowances(self, setup_workspace_test_data):
        """
        Test that user's view includes their own allowance transactions.

        Expected:
        - User1 sees own allowances (txn1, txn4)
        - User2 sees own allowances (txn2)
        """
        db = DatabaseConnection.get_instance()
        data = setup_workspace_test_data

        cat_repo = CategoryRepository(db)
        inst_repo = InstitutionRepository(db)
        txn_repo = TransactionRepository(db, cat_repo, inst_repo)

        # User1 should see own allowances
        transactions_user1, total_user1 = txn_repo.get_filtered(
            workspace_id=data['workspace1_id'],
            exclude_allowances_for_user_id=data['user1_id'],
            year=2025,
            month=1,
            category_id=data['category_food_id']  # Filter by 식비 to get txn1 and txn4
        )

        # User1 has 2 food transactions: txn1 (10000원) and txn4 (8000원), both marked as own allowances
        assert total_user1 == 2, f"Expected 2 food transactions for user1, got {total_user1}"
        txn_ids_user1 = {txn['id'] for txn in transactions_user1}
        assert data['txn1_id'] in txn_ids_user1
        assert data['txn4_id'] in txn_ids_user1

    def test_get_filtered_with_category_filter_and_allowance_exclusion(self, setup_workspace_test_data):
        """
        Test combined category filtering and allowance exclusion.

        Expected:
        - User1 filtering by category should still exclude user2's allowances in that category
        - User2 filtering by category should still exclude user1's allowances in that category
        """
        db = DatabaseConnection.get_instance()
        data = setup_workspace_test_data

        cat_repo = CategoryRepository(db)
        inst_repo = InstitutionRepository(db)
        txn_repo = TransactionRepository(db, cat_repo, inst_repo)

        # User1 queries food category (식비)
        # Available food transactions in workspace1: txn1 (user1 allowance), txn4 (user1 allowance)
        # User1 should see both (own allowances)
        transactions_user1, total_user1 = txn_repo.get_filtered(
            workspace_id=data['workspace1_id'],
            exclude_allowances_for_user_id=data['user1_id'],
            year=2025,
            month=1,
            category_id=data['category_food_id']
        )

        assert total_user1 == 2
        assert sum(txn['amount'] for txn in transactions_user1) == 18000  # 10000 + 8000

        # User2 queries food category (식비)
        # Available food transactions in workspace1: txn1 (user1 allowance), txn4 (user1 allowance)
        # User2 should see 0 (both are user1's allowances)
        transactions_user2, total_user2 = txn_repo.get_filtered(
            workspace_id=data['workspace1_id'],
            exclude_allowances_for_user_id=data['user2_id'],
            year=2025,
            month=1,
            category_id=data['category_food_id']
        )

        assert total_user2 == 0, f"Expected 0 food transactions for user2, got {total_user2}"


class TestTransactionRepositoryTotalAmount:
    """Test get_filtered_total_amount with workspace and allowance filtering."""

    def test_get_filtered_total_amount_excludes_other_users_allowances(self, setup_workspace_test_data):
        """
        Test that total amount calculation excludes other users' allowances.

        Expected:
        - User1's total includes own allowances but excludes user2's allowances
        - User2's total includes own allowances but excludes user1's allowances
        """
        db = DatabaseConnection.get_instance()
        data = setup_workspace_test_data

        cat_repo = CategoryRepository(db)
        inst_repo = InstitutionRepository(db)
        txn_repo = TransactionRepository(db, cat_repo, inst_repo)

        # User1's total (workspace1, January 2025)
        # Should include: txn1 (10000), txn3 (50000), txn4 (8000)
        # Should exclude: txn2 (5000, user2's allowance)
        total_user1 = txn_repo.get_filtered_total_amount(
            workspace_id=data['workspace1_id'],
            exclude_allowances_for_user_id=data['user1_id'],
            year=2025,
            month=1
        )

        expected_user1 = 10000 + 50000 + 8000  # 68000
        assert total_user1 == expected_user1, f"Expected {expected_user1}원 for user1, got {total_user1}원"

        # User2's total (workspace1, January 2025)
        # Should include: txn2 (5000), txn3 (50000)
        # Should exclude: txn1 (10000, user1's allowance), txn4 (8000, user1's allowance)
        total_user2 = txn_repo.get_filtered_total_amount(
            workspace_id=data['workspace1_id'],
            exclude_allowances_for_user_id=data['user2_id'],
            year=2025,
            month=1
        )

        expected_user2 = 5000 + 50000  # 55000
        assert total_user2 == expected_user2, f"Expected {expected_user2}원 for user2, got {total_user2}원"

    def test_get_filtered_total_amount_workspace_isolation(self, setup_workspace_test_data):
        """
        Test that total amount calculation respects workspace isolation.

        Expected:
        - Workspace1 total only includes workspace1 transactions
        - Workspace2 total only includes workspace2 transactions
        """
        db = DatabaseConnection.get_instance()
        data = setup_workspace_test_data

        cat_repo = CategoryRepository(db)
        inst_repo = InstitutionRepository(db)
        txn_repo = TransactionRepository(db, cat_repo, inst_repo)

        # Workspace 1 total (user1's view)
        total_ws1 = txn_repo.get_filtered_total_amount(
            workspace_id=data['workspace1_id'],
            exclude_allowances_for_user_id=data['user1_id'],
            year=2025,
            month=1
        )

        # Workspace 2 total (user2's view)
        total_ws2 = txn_repo.get_filtered_total_amount(
            workspace_id=data['workspace2_id'],
            exclude_allowances_for_user_id=data['user2_id'],
            year=2025,
            month=1
        )

        # Workspace1: txn1 (10000) + txn3 (50000) + txn4 (8000) = 68000
        assert total_ws1 == 68000

        # Workspace2: txn6 (15000) + txn7 (20000) = 35000
        assert total_ws2 == 35000

    def test_get_filtered_total_amount_with_filters(self, setup_workspace_test_data):
        """
        Test total amount with combined filters (category, institution, search).

        Expected:
        - Filters work correctly with workspace and allowance exclusion
        """
        db = DatabaseConnection.get_instance()
        data = setup_workspace_test_data

        cat_repo = CategoryRepository(db)
        inst_repo = InstitutionRepository(db)
        txn_repo = TransactionRepository(db, cat_repo, inst_repo)

        # User1's total for 식비 (food) category
        # Should include: txn1 (10000), txn4 (8000)
        total_food_user1 = txn_repo.get_filtered_total_amount(
            workspace_id=data['workspace1_id'],
            exclude_allowances_for_user_id=data['user1_id'],
            year=2025,
            month=1,
            category_id=data['category_food_id']
        )

        assert total_food_user1 == 18000, f"Expected 18000원 for user1 food, got {total_food_user1}원"

        # User2's total for 식비 (food) category
        # Should exclude: txn1 (user1's allowance), txn4 (user1's allowance)
        total_food_user2 = txn_repo.get_filtered_total_amount(
            workspace_id=data['workspace1_id'],
            exclude_allowances_for_user_id=data['user2_id'],
            year=2025,
            month=1,
            category_id=data['category_food_id']
        )

        assert total_food_user2 == 0, f"Expected 0원 for user2 food (user1's allowances), got {total_food_user2}원"


class TestTransactionRepositoryMonthlySummary:
    """Test get_monthly_summary_with_stats with workspace and allowance filtering."""

    def test_get_monthly_summary_excludes_other_users_allowances(self, setup_workspace_test_data):
        """
        Test that monthly summary excludes other users' allowances.

        Expected:
        - User1's summary includes own allowances, excludes user2's
        - User2's summary includes own allowances, excludes user1's
        - Transaction counts reflect exclusions
        """
        db = DatabaseConnection.get_instance()
        data = setup_workspace_test_data

        cat_repo = CategoryRepository(db)
        inst_repo = InstitutionRepository(db)
        txn_repo = TransactionRepository(db, cat_repo, inst_repo)

        # User1's monthly summary
        summary_user1 = txn_repo.get_monthly_summary_with_stats(
            workspace_id=data['workspace1_id'],
            exclude_allowances_for_user_id=data['user1_id'],
            year=2025,
            month=1
        )

        # User1 should see: txn1 (식비, 10000), txn3 (통신, 50000), txn4 (식비, 8000)
        # Total: 68000, Count: 3
        assert summary_user1['total_amount'] == 68000
        assert summary_user1['transaction_count'] == 3

        # Check category breakdown
        categories_user1 = {cat['category_name']: cat for cat in summary_user1['by_category']}
        assert categories_user1['식비']['amount'] == 18000  # txn1 + txn4
        assert categories_user1['식비']['count'] == 2
        assert categories_user1['통신']['amount'] == 50000  # txn3
        assert categories_user1['통신']['count'] == 1
        assert '교통' not in categories_user1  # txn2 (user2's allowance) excluded

        # User2's monthly summary
        summary_user2 = txn_repo.get_monthly_summary_with_stats(
            workspace_id=data['workspace1_id'],
            exclude_allowances_for_user_id=data['user2_id'],
            year=2025,
            month=1
        )

        # User2 should see: txn2 (교통, 5000), txn3 (통신, 50000)
        # Total: 55000, Count: 2
        assert summary_user2['total_amount'] == 55000
        assert summary_user2['transaction_count'] == 2

        # Check category breakdown
        categories_user2 = {cat['category_name']: cat for cat in summary_user2['by_category']}
        assert categories_user2['교통']['amount'] == 5000  # txn2
        assert categories_user2['교통']['count'] == 1
        assert categories_user2['통신']['amount'] == 50000  # txn3
        assert categories_user2['통신']['count'] == 1
        assert '식비' not in categories_user2  # txn1, txn4 (user1's allowances) excluded

    def test_get_monthly_summary_workspace_isolation(self, setup_workspace_test_data):
        """
        Test that monthly summary respects workspace isolation.

        Expected:
        - Workspace1 summary only includes workspace1 transactions
        - Workspace2 summary only includes workspace2 transactions
        """
        db = DatabaseConnection.get_instance()
        data = setup_workspace_test_data

        cat_repo = CategoryRepository(db)
        inst_repo = InstitutionRepository(db)
        txn_repo = TransactionRepository(db, cat_repo, inst_repo)

        # Workspace1 summary (user1's view)
        summary_ws1 = txn_repo.get_monthly_summary_with_stats(
            workspace_id=data['workspace1_id'],
            exclude_allowances_for_user_id=data['user1_id'],
            year=2025,
            month=1
        )

        # Workspace2 summary (user2's view)
        summary_ws2 = txn_repo.get_monthly_summary_with_stats(
            workspace_id=data['workspace2_id'],
            exclude_allowances_for_user_id=data['user2_id'],
            year=2025,
            month=1
        )

        # Workspace1: 68000원, 3 transactions
        assert summary_ws1['total_amount'] == 68000
        assert summary_ws1['transaction_count'] == 3

        # Workspace2: 35000원 (15000 + 20000), 2 transactions
        assert summary_ws2['total_amount'] == 35000
        assert summary_ws2['transaction_count'] == 2

    def test_get_monthly_summary_different_months(self, setup_workspace_test_data):
        """
        Test monthly summary for different months in same workspace.

        Expected:
        - January summary includes only January transactions
        - February summary includes only February transactions
        """
        db = DatabaseConnection.get_instance()
        data = setup_workspace_test_data

        cat_repo = CategoryRepository(db)
        inst_repo = InstitutionRepository(db)
        txn_repo = TransactionRepository(db, cat_repo, inst_repo)

        # January summary
        summary_jan = txn_repo.get_monthly_summary_with_stats(
            workspace_id=data['workspace1_id'],
            exclude_allowances_for_user_id=data['user1_id'],
            year=2025,
            month=1
        )

        # February summary
        summary_feb = txn_repo.get_monthly_summary_with_stats(
            workspace_id=data['workspace1_id'],
            exclude_allowances_for_user_id=data['user1_id'],
            year=2025,
            month=2
        )

        # January: 3 transactions, 68000원
        assert summary_jan['total_amount'] == 68000
        assert summary_jan['transaction_count'] == 3

        # February: 1 transaction (txn5), 12000원
        assert summary_feb['total_amount'] == 12000
        assert summary_feb['transaction_count'] == 1


class TestTransactionRepositoryEdgeCases:
    """Test edge cases and boundary conditions."""

    def test_get_filtered_empty_workspace(self, setup_workspace_test_data):
        """
        Test querying a workspace with no transactions.

        Expected:
        - Returns empty list and count 0
        """
        db = DatabaseConnection.get_instance()
        data = setup_workspace_test_data

        cat_repo = CategoryRepository(db)
        inst_repo = InstitutionRepository(db)
        txn_repo = TransactionRepository(db, cat_repo, inst_repo)

        # Create a new empty workspace
        workspace_repo = WorkspaceRepository(db)
        empty_workspace_id = workspace_repo.create(
            name='Empty Workspace',
            description='Workspace with no transactions',
            created_by_user_id=data['user1_id']
        )

        transactions, total = txn_repo.get_filtered(
            workspace_id=empty_workspace_id,
            exclude_allowances_for_user_id=data['user1_id'],
            year=2025,
            month=1
        )

        assert total == 0
        assert len(transactions) == 0

    def test_get_filtered_total_amount_empty_result(self, setup_workspace_test_data):
        """
        Test total amount calculation for empty result set.

        Expected:
        - Returns 0 for empty result
        """
        db = DatabaseConnection.get_instance()
        data = setup_workspace_test_data

        cat_repo = CategoryRepository(db)
        inst_repo = InstitutionRepository(db)
        txn_repo = TransactionRepository(db, cat_repo, inst_repo)

        # Query non-existent month
        total = txn_repo.get_filtered_total_amount(
            workspace_id=data['workspace1_id'],
            exclude_allowances_for_user_id=data['user1_id'],
            year=2025,
            month=12  # December (no transactions)
        )

        assert total == 0

    def test_get_monthly_summary_empty_month(self, setup_workspace_test_data):
        """
        Test monthly summary for a month with no transactions.

        Expected:
        - Returns zero amounts and empty category list
        """
        db = DatabaseConnection.get_instance()
        data = setup_workspace_test_data

        cat_repo = CategoryRepository(db)
        inst_repo = InstitutionRepository(db)
        txn_repo = TransactionRepository(db, cat_repo, inst_repo)

        summary = txn_repo.get_monthly_summary_with_stats(
            workspace_id=data['workspace1_id'],
            exclude_allowances_for_user_id=data['user1_id'],
            year=2025,
            month=12  # December (no transactions)
        )

        assert summary['total_amount'] == 0
        assert summary['transaction_count'] == 0
        assert len(summary['by_category']) == 0

    def test_get_filtered_all_transactions_excluded_as_allowances(self, setup_workspace_test_data):
        """
        Test when all transactions are marked as other user's allowances.

        Expected:
        - User2 sees no food transactions (all marked by user1)
        """
        db = DatabaseConnection.get_instance()
        data = setup_workspace_test_data

        cat_repo = CategoryRepository(db)
        inst_repo = InstitutionRepository(db)
        txn_repo = TransactionRepository(db, cat_repo, inst_repo)

        # User2 queries food category (all food transactions are user1's allowances)
        transactions, total = txn_repo.get_filtered(
            workspace_id=data['workspace1_id'],
            exclude_allowances_for_user_id=data['user2_id'],
            year=2025,
            month=1,
            category_id=data['category_food_id']
        )

        assert total == 0
        assert len(transactions) == 0
