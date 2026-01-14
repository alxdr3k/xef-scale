"""
Comprehensive integration tests for allowance privacy enforcement.

CRITICAL FEATURE: Privacy is the primary feature of the allowance system.
User A's allowances must be completely hidden from User B across ALL API endpoints.

Test Coverage:
- Transaction list privacy (User B cannot see User A's allowances)
- Total amount calculations exclude other users' allowances
- Monthly summaries exclude other users' allowances
- Allowance list privacy (User B cannot see User A's allowances)
- Unmark restores visibility to all users
- Multiple users marking different transactions
- Same transaction marked by multiple users
- Cross-workspace privacy isolation
"""

import pytest
import sqlite3
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


@pytest.fixture
def db_with_users_and_workspace(test_db_override):
    """
    Create test database with 2 users in 1 workspace with sample transactions.

    Setup:
    - User 1 (OWNER) and User 2 (MEMBER_WRITE) in Workspace 1
    - 2 transactions (5000, 3000) in the workspace
    - Category: 식비 (food)
    - Institution: 신한카드

    Returns:
        dict with:
        - db: Database connection
        - workspace_id: Test workspace ID
        - user1_id, user2_id: User IDs
        - transaction1_id, transaction2_id: Transaction IDs (amounts 5000, 3000)
        - category_id, institution_id: Reference data IDs
    """
    db = DatabaseConnection.get_instance()

    # Create users
    user_repo = UserRepository(db)
    user1_id = user_repo.create_user(
        email="privacy_user1@test.com",
        google_id="google_privacy_1",
        name="Privacy User 1"
    )
    user2_id = user_repo.create_user(
        email="privacy_user2@test.com",
        google_id="google_privacy_2",
        name="Privacy User 2"
    )

    # Create workspace
    workspace_repo = WorkspaceRepository(db)
    workspace_id = workspace_repo.create(
        name="Privacy Test Workspace",
        description="Test workspace for privacy tests",
        created_by_user_id=user1_id
    )

    # Add both users as members
    membership_repo = WorkspaceMembershipRepository(db)
    membership_repo.add_member(workspace_id, user2_id, "MEMBER_WRITE")

    # Create category and institution
    cat_repo = CategoryRepository(db)
    inst_repo = InstitutionRepository(db)
    category_id = cat_repo.get_or_create('식비')
    institution_id = inst_repo.get_or_create('신한카드')

    # Create test transactions
    txn_repo = TransactionRepository(db, cat_repo, inst_repo)

    # Transaction 1: 5000원 (will be marked as User A's allowance)
    cursor = db.execute('''
        INSERT INTO transactions (
            workspace_id, transaction_date, transaction_year, transaction_month,
            category_id, merchant_name, amount, institution_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ''', (workspace_id, '2025-01-15', 2025, 1, category_id, 'Restaurant A', 5000, institution_id))
    transaction1_id = cursor.lastrowid

    # Transaction 2: 3000원 (remains unmarked)
    cursor = db.execute('''
        INSERT INTO transactions (
            workspace_id, transaction_date, transaction_year, transaction_month,
            category_id, merchant_name, amount, institution_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ''', (workspace_id, '2025-01-16', 2025, 1, category_id, 'Restaurant B', 3000, institution_id))
    transaction2_id = cursor.lastrowid

    db.commit()

    yield {
        "db": db,
        "workspace_id": workspace_id,
        "user1_id": user1_id,
        "user2_id": user2_id,
        "transaction1_id": transaction1_id,
        "transaction2_id": transaction2_id,
        "category_id": category_id,
        "institution_id": institution_id
    }


class TestAllowancePrivacyTransactionList:
    """Test privacy enforcement in transaction list queries."""

    def test_user_a_marks_allowance_hidden_from_user_b_transaction_list(self, db_with_users_and_workspace):
        """
        CRITICAL: User B cannot see transactions marked as allowance by User A.

        Scenario:
        1. User A marks transaction1 (5000원) as allowance
        2. User B queries transaction list
        3. User B should NOT see transaction1
        4. User A queries transaction list
        5. User A SHOULD see transaction1
        """
        data = db_with_users_and_workspace
        db = data["db"]

        # User A marks transaction1 as allowance
        AllowanceTransactionRepository.mark_as_allowance(
            db,
            transaction_id=data["transaction1_id"],
            user_id=data["user1_id"],
            workspace_id=data["workspace_id"]
        )

        # Initialize repository
        cat_repo = CategoryRepository(db)
        inst_repo = InstitutionRepository(db)
        txn_repo = TransactionRepository(db, cat_repo, inst_repo)

        # User B queries transactions (should NOT see transaction1)
        user_b_transactions, user_b_total = txn_repo.get_filtered(
            workspace_id=data["workspace_id"],
            exclude_allowances_for_user_id=data["user2_id"],
            year=2025,
            month=1
        )

        transaction_ids_b = [t['id'] for t in user_b_transactions]
        assert data["transaction1_id"] not in transaction_ids_b, \
            "User B should NOT see User A's allowance transaction"
        assert data["transaction2_id"] in transaction_ids_b, \
            "User B should see non-allowance transactions"
        assert user_b_total == 1, "User B should see only 1 transaction"

        # User A queries transactions (SHOULD see transaction1)
        user_a_transactions, user_a_total = txn_repo.get_filtered(
            workspace_id=data["workspace_id"],
            exclude_allowances_for_user_id=data["user1_id"],
            year=2025,
            month=1
        )

        transaction_ids_a = [t['id'] for t in user_a_transactions]
        assert data["transaction1_id"] in transaction_ids_a, \
            "User A should see their own allowance transaction"
        assert data["transaction2_id"] in transaction_ids_a, \
            "User A should see non-allowance transactions"
        assert user_a_total == 2, "User A should see both transactions"

    def test_unmarked_transactions_visible_to_all_users(self, db_with_users_and_workspace):
        """
        All users should see transactions that are NOT marked as allowance.

        Baseline test to ensure default visibility works correctly.
        """
        data = db_with_users_and_workspace
        db = data["db"]

        # Initialize repository
        cat_repo = CategoryRepository(db)
        inst_repo = InstitutionRepository(db)
        txn_repo = TransactionRepository(db, cat_repo, inst_repo)

        # User A sees both transactions
        user_a_transactions, user_a_total = txn_repo.get_filtered(
            workspace_id=data["workspace_id"],
            exclude_allowances_for_user_id=data["user1_id"],
            year=2025,
            month=1
        )
        assert user_a_total == 2, "User A should see both unmarked transactions"

        # User B also sees both transactions
        user_b_transactions, user_b_total = txn_repo.get_filtered(
            workspace_id=data["workspace_id"],
            exclude_allowances_for_user_id=data["user2_id"],
            year=2025,
            month=1
        )
        assert user_b_total == 2, "User B should see both unmarked transactions"


class TestAllowancePrivacyTotalAmount:
    """Test privacy enforcement in total amount calculations."""

    def test_user_b_total_amount_excludes_user_a_allowances(self, db_with_users_and_workspace):
        """
        CRITICAL: User B's total amounts should NOT include User A's allowances.

        Scenario:
        1. User A marks transaction1 (5000) as allowance
        2. User B's total should be 3000 (only transaction2)
        3. User A's total should be 8000 (both transactions)
        """
        data = db_with_users_and_workspace
        db = data["db"]

        # User A marks transaction1 as allowance
        AllowanceTransactionRepository.mark_as_allowance(
            db,
            transaction_id=data["transaction1_id"],
            user_id=data["user1_id"],
            workspace_id=data["workspace_id"]
        )

        # Initialize repository
        cat_repo = CategoryRepository(db)
        inst_repo = InstitutionRepository(db)
        txn_repo = TransactionRepository(db, cat_repo, inst_repo)

        # User B's total (should exclude transaction1)
        user_b_total = txn_repo.get_filtered_total_amount(
            workspace_id=data["workspace_id"],
            exclude_allowances_for_user_id=data["user2_id"],
            year=2025,
            month=1
        )

        assert user_b_total == 3000, \
            f"User B's total should be 3000 (excluding User A's allowance), got {user_b_total}"

        # User A's total (should include both)
        user_a_total = txn_repo.get_filtered_total_amount(
            workspace_id=data["workspace_id"],
            exclude_allowances_for_user_id=data["user1_id"],
            year=2025,
            month=1
        )

        assert user_a_total == 8000, \
            f"User A's total should be 8000 (including own allowance), got {user_a_total}"

    def test_total_amount_with_filters_respects_privacy(self, db_with_users_and_workspace):
        """
        Privacy should be enforced even when using filters (category, institution, search).
        """
        data = db_with_users_and_workspace
        db = data["db"]

        # User A marks transaction1 as allowance
        AllowanceTransactionRepository.mark_as_allowance(
            db,
            transaction_id=data["transaction1_id"],
            user_id=data["user1_id"],
            workspace_id=data["workspace_id"]
        )

        # Initialize repository
        cat_repo = CategoryRepository(db)
        inst_repo = InstitutionRepository(db)
        txn_repo = TransactionRepository(db, cat_repo, inst_repo)

        # User B's total with category filter
        user_b_total = txn_repo.get_filtered_total_amount(
            workspace_id=data["workspace_id"],
            exclude_allowances_for_user_id=data["user2_id"],
            year=2025,
            month=1,
            category_id=data["category_id"]
        )

        assert user_b_total == 3000, \
            f"User B's filtered total should be 3000, got {user_b_total}"


class TestAllowancePrivacyMonthlySummary:
    """Test privacy enforcement in monthly summary calculations."""

    def test_user_b_monthly_summary_excludes_user_a_allowances(self, db_with_users_and_workspace):
        """
        CRITICAL: User B's monthly summary should NOT include User A's allowances.

        Scenario:
        1. User A marks transaction1 as allowance
        2. User B's summary should show total_amount = 3000, count = 1
        3. User A's summary should show total_amount = 8000, count = 2
        """
        data = db_with_users_and_workspace
        db = data["db"]

        # User A marks transaction1 as allowance
        AllowanceTransactionRepository.mark_as_allowance(
            db,
            transaction_id=data["transaction1_id"],
            user_id=data["user1_id"],
            workspace_id=data["workspace_id"]
        )

        # Initialize repository
        cat_repo = CategoryRepository(db)
        inst_repo = InstitutionRepository(db)
        txn_repo = TransactionRepository(db, cat_repo, inst_repo)

        # User B's summary
        user_b_summary = txn_repo.get_monthly_summary_with_stats(
            workspace_id=data["workspace_id"],
            exclude_allowances_for_user_id=data["user2_id"],
            year=2025,
            month=1
        )

        assert user_b_summary['total_amount'] == 3000, \
            f"User B's summary total should be 3000, got {user_b_summary['total_amount']}"
        assert user_b_summary['transaction_count'] == 1, \
            f"User B's summary count should be 1, got {user_b_summary['transaction_count']}"

        # User A's summary
        user_a_summary = txn_repo.get_monthly_summary_with_stats(
            workspace_id=data["workspace_id"],
            exclude_allowances_for_user_id=data["user1_id"],
            year=2025,
            month=1
        )

        assert user_a_summary['total_amount'] == 8000, \
            f"User A's summary total should be 8000, got {user_a_summary['total_amount']}"
        assert user_a_summary['transaction_count'] == 2, \
            f"User A's summary count should be 2, got {user_a_summary['transaction_count']}"

    def test_category_breakdown_respects_privacy(self, db_with_users_and_workspace):
        """
        Category breakdown in monthly summary should respect allowance privacy.
        """
        data = db_with_users_and_workspace
        db = data["db"]

        # User A marks transaction1 as allowance
        AllowanceTransactionRepository.mark_as_allowance(
            db,
            transaction_id=data["transaction1_id"],
            user_id=data["user1_id"],
            workspace_id=data["workspace_id"]
        )

        # Initialize repository
        cat_repo = CategoryRepository(db)
        inst_repo = InstitutionRepository(db)
        txn_repo = TransactionRepository(db, cat_repo, inst_repo)

        # User B's summary
        user_b_summary = txn_repo.get_monthly_summary_with_stats(
            workspace_id=data["workspace_id"],
            exclude_allowances_for_user_id=data["user2_id"],
            year=2025,
            month=1
        )

        # Check category breakdown
        category_food = next(
            (cat for cat in user_b_summary['by_category'] if cat['category_id'] == data['category_id']),
            None
        )
        assert category_food is not None, "Food category should exist"
        assert category_food['amount'] == 3000, \
            f"User B's food category amount should be 3000, got {category_food['amount']}"
        assert category_food['count'] == 1, \
            f"User B's food category count should be 1, got {category_food['count']}"


class TestAllowancePrivacyAllowanceList:
    """Test privacy enforcement in allowance list queries."""

    def test_user_b_cannot_see_user_a_allowances_in_allowance_list(self, db_with_users_and_workspace):
        """
        User B's allowance list should be empty (cannot see User A's allowances).

        Each user only sees their own allowances, never other users' allowances.
        """
        data = db_with_users_and_workspace
        db = data["db"]

        # User A marks transaction1 as allowance
        AllowanceTransactionRepository.mark_as_allowance(
            db,
            transaction_id=data["transaction1_id"],
            user_id=data["user1_id"],
            workspace_id=data["workspace_id"]
        )

        # User B queries allowances (should be empty)
        user_b_allowances, user_b_count = AllowanceTransactionRepository.get_user_allowances(
            db,
            user_id=data["user2_id"],
            workspace_id=data["workspace_id"]
        )

        assert user_b_count == 0, "User B should have no allowances"
        assert len(user_b_allowances) == 0, "User B's allowance list should be empty"

        # User A queries allowances (should have 1)
        user_a_allowances, user_a_count = AllowanceTransactionRepository.get_user_allowances(
            db,
            user_id=data["user1_id"],
            workspace_id=data["workspace_id"]
        )

        assert user_a_count == 1, "User A should have 1 allowance"
        assert user_a_allowances[0]['id'] == data["transaction1_id"], \
            "User A's allowance should be transaction1"

    def test_allowance_list_with_filters_respects_privacy(self, db_with_users_and_workspace):
        """
        Filtered allowance queries should still respect privacy.
        """
        data = db_with_users_and_workspace
        db = data["db"]

        # User A marks both transactions as allowances
        AllowanceTransactionRepository.mark_as_allowance(
            db,
            transaction_id=data["transaction1_id"],
            user_id=data["user1_id"],
            workspace_id=data["workspace_id"]
        )
        AllowanceTransactionRepository.mark_as_allowance(
            db,
            transaction_id=data["transaction2_id"],
            user_id=data["user1_id"],
            workspace_id=data["workspace_id"]
        )

        # User B queries with filters (should still be empty)
        user_b_allowances, user_b_count = AllowanceTransactionRepository.get_user_allowances(
            db,
            user_id=data["user2_id"],
            workspace_id=data["workspace_id"],
            filters={'year': 2025, 'month': 1}
        )

        assert user_b_count == 0, "User B should have no allowances even with filters"

        # User A queries with filters (should have 2)
        user_a_allowances, user_a_count = AllowanceTransactionRepository.get_user_allowances(
            db,
            user_id=data["user1_id"],
            workspace_id=data["workspace_id"],
            filters={'year': 2025, 'month': 1}
        )

        assert user_a_count == 2, "User A should have 2 allowances with filters"


class TestAllowancePrivacyUnmark:
    """Test visibility restoration after unmarking allowances."""

    def test_unmark_allowance_restores_visibility_to_all_users(self, db_with_users_and_workspace):
        """
        After unmarking allowance, transaction becomes visible to all users again.

        Scenario:
        1. User A marks transaction1 as allowance
        2. User B cannot see transaction1
        3. User A unmarks transaction1
        4. User B can now see transaction1
        """
        data = db_with_users_and_workspace
        db = data["db"]

        # Initialize repository
        cat_repo = CategoryRepository(db)
        inst_repo = InstitutionRepository(db)
        txn_repo = TransactionRepository(db, cat_repo, inst_repo)

        # User A marks and then unmarks
        AllowanceTransactionRepository.mark_as_allowance(
            db,
            transaction_id=data["transaction1_id"],
            user_id=data["user1_id"],
            workspace_id=data["workspace_id"]
        )

        # Verify User B cannot see it
        user_b_before, count_before = txn_repo.get_filtered(
            workspace_id=data["workspace_id"],
            exclude_allowances_for_user_id=data["user2_id"],
            year=2025,
            month=1
        )
        assert count_before == 1, "User B should see 1 transaction before unmark"

        # User A unmarks
        success = AllowanceTransactionRepository.unmark_allowance(
            db,
            transaction_id=data["transaction1_id"],
            user_id=data["user1_id"],
            workspace_id=data["workspace_id"]
        )
        assert success is True, "Unmark should succeed"

        # User B should now see transaction1
        user_b_after, count_after = txn_repo.get_filtered(
            workspace_id=data["workspace_id"],
            exclude_allowances_for_user_id=data["user2_id"],
            year=2025,
            month=1
        )

        transaction_ids = [t['id'] for t in user_b_after]
        assert data["transaction1_id"] in transaction_ids, \
            "After unmarking, User B should see transaction1"
        assert count_after == 2, "User B should see both transactions after unmark"

    def test_unmark_restores_amounts_in_calculations(self, db_with_users_and_workspace):
        """
        Unmarking should restore transaction amounts in User B's totals.
        """
        data = db_with_users_and_workspace
        db = data["db"]

        # Initialize repository
        cat_repo = CategoryRepository(db)
        inst_repo = InstitutionRepository(db)
        txn_repo = TransactionRepository(db, cat_repo, inst_repo)

        # User A marks transaction1
        AllowanceTransactionRepository.mark_as_allowance(
            db,
            transaction_id=data["transaction1_id"],
            user_id=data["user1_id"],
            workspace_id=data["workspace_id"]
        )

        # User B's total before unmark
        total_before = txn_repo.get_filtered_total_amount(
            workspace_id=data["workspace_id"],
            exclude_allowances_for_user_id=data["user2_id"],
            year=2025,
            month=1
        )
        assert total_before == 3000, "User B's total should be 3000 before unmark"

        # User A unmarks
        AllowanceTransactionRepository.unmark_allowance(
            db,
            transaction_id=data["transaction1_id"],
            user_id=data["user1_id"],
            workspace_id=data["workspace_id"]
        )

        # User B's total after unmark
        total_after = txn_repo.get_filtered_total_amount(
            workspace_id=data["workspace_id"],
            exclude_allowances_for_user_id=data["user2_id"],
            year=2025,
            month=1
        )
        assert total_after == 8000, "User B's total should be 8000 after unmark"


class TestAllowancePrivacyMultipleUsers:
    """Test privacy with multiple users marking different transactions."""

    def test_multiple_users_mark_different_transactions(self, db_with_users_and_workspace):
        """
        When User A and User B each mark different transactions:
        - User A should NOT see User B's allowance
        - User B should NOT see User A's allowance
        - Each sees their own allowances
        """
        data = db_with_users_and_workspace
        db = data["db"]

        # User A marks transaction1, User B marks transaction2
        AllowanceTransactionRepository.mark_as_allowance(
            db,
            transaction_id=data["transaction1_id"],
            user_id=data["user1_id"],
            workspace_id=data["workspace_id"]
        )
        AllowanceTransactionRepository.mark_as_allowance(
            db,
            transaction_id=data["transaction2_id"],
            user_id=data["user2_id"],
            workspace_id=data["workspace_id"]
        )

        # Initialize repository
        cat_repo = CategoryRepository(db)
        inst_repo = InstitutionRepository(db)
        txn_repo = TransactionRepository(db, cat_repo, inst_repo)

        # User A should only see transaction1 (NOT transaction2)
        user_a_transactions, user_a_count = txn_repo.get_filtered(
            workspace_id=data["workspace_id"],
            exclude_allowances_for_user_id=data["user1_id"],
            year=2025,
            month=1
        )
        transaction_ids_a = [t['id'] for t in user_a_transactions]
        assert data["transaction1_id"] in transaction_ids_a, "User A should see own allowance"
        assert data["transaction2_id"] not in transaction_ids_a, "User A should NOT see User B's allowance"
        assert user_a_count == 1, "User A should see only 1 transaction"

        # User B should only see transaction2 (NOT transaction1)
        user_b_transactions, user_b_count = txn_repo.get_filtered(
            workspace_id=data["workspace_id"],
            exclude_allowances_for_user_id=data["user2_id"],
            year=2025,
            month=1
        )
        transaction_ids_b = [t['id'] for t in user_b_transactions]
        assert data["transaction2_id"] in transaction_ids_b, "User B should see own allowance"
        assert data["transaction1_id"] not in transaction_ids_b, "User B should NOT see User A's allowance"
        assert user_b_count == 1, "User B should see only 1 transaction"

    def test_same_transaction_marked_by_multiple_users(self, db_with_users_and_workspace):
        """
        When both User A and User B mark the SAME transaction as allowance:
        - Both users should see the transaction
        - Duplicate marking is allowed (separate allowance records)
        """
        data = db_with_users_and_workspace
        db = data["db"]

        # Both users mark transaction1
        allowance_id_a = AllowanceTransactionRepository.mark_as_allowance(
            db,
            transaction_id=data["transaction1_id"],
            user_id=data["user1_id"],
            workspace_id=data["workspace_id"],
            notes="User A's personal allowance"
        )
        allowance_id_b = AllowanceTransactionRepository.mark_as_allowance(
            db,
            transaction_id=data["transaction1_id"],
            user_id=data["user2_id"],
            workspace_id=data["workspace_id"],
            notes="User B's personal allowance"
        )

        assert allowance_id_a != allowance_id_b, "Should create separate allowance records"

        # Initialize repository
        cat_repo = CategoryRepository(db)
        inst_repo = InstitutionRepository(db)
        txn_repo = TransactionRepository(db, cat_repo, inst_repo)

        # Both users should see transaction1 (it's their own allowance)
        user_a_transactions, user_a_count = txn_repo.get_filtered(
            workspace_id=data["workspace_id"],
            exclude_allowances_for_user_id=data["user1_id"],
            year=2025,
            month=1
        )
        transaction_ids_a = [t['id'] for t in user_a_transactions]
        assert data["transaction1_id"] in transaction_ids_a, "User A should see transaction1"

        user_b_transactions, user_b_count = txn_repo.get_filtered(
            workspace_id=data["workspace_id"],
            exclude_allowances_for_user_id=data["user2_id"],
            year=2025,
            month=1
        )
        transaction_ids_b = [t['id'] for t in user_b_transactions]
        assert data["transaction1_id"] in transaction_ids_b, "User B should see transaction1"


class TestAllowancePrivacyCrossWorkspace:
    """Test privacy isolation across workspaces."""

    def test_allowance_in_workspace1_does_not_affect_workspace2(self, test_db_override):
        """
        User A's allowance in Workspace 1 should not affect queries in Workspace 2.

        Cross-workspace isolation is critical for multi-tenant privacy.
        """
        db = DatabaseConnection.get_instance()

        # Create users
        user_repo = UserRepository(db)
        user1_id = user_repo.create_user(
            email="cross_ws_user1@test.com",
            google_id="google_cross_ws_1",
            name="Cross WS User 1"
        )
        user2_id = user_repo.create_user(
            email="cross_ws_user2@test.com",
            google_id="google_cross_ws_2",
            name="Cross WS User 2"
        )

        # Create two workspaces
        workspace_repo = WorkspaceRepository(db)
        workspace1_id = workspace_repo.create(
            name="Cross WS 1",
            description="Workspace 1",
            created_by_user_id=user1_id
        )
        workspace2_id = workspace_repo.create(
            name="Cross WS 2",
            description="Workspace 2",
            created_by_user_id=user1_id
        )

        # Add User 2 to both workspaces
        membership_repo = WorkspaceMembershipRepository(db)
        membership_repo.add_member(workspace1_id, user2_id, "MEMBER_WRITE")
        membership_repo.add_member(workspace2_id, user2_id, "MEMBER_WRITE")

        # Create category and institution
        cat_repo = CategoryRepository(db)
        inst_repo = InstitutionRepository(db)
        category_id = cat_repo.get_or_create('식비')
        institution_id = inst_repo.get_or_create('신한카드')

        # Create transaction in Workspace 1
        cursor = db.execute('''
            INSERT INTO transactions (
                workspace_id, transaction_date, transaction_year, transaction_month,
                category_id, merchant_name, amount, institution_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''', (workspace1_id, '2025-01-15', 2025, 1, category_id, 'Restaurant A', 5000, institution_id))
        transaction_ws1_id = cursor.lastrowid

        # Create transaction in Workspace 2 (different merchant name to avoid duplicate detection)
        cursor = db.execute('''
            INSERT INTO transactions (
                workspace_id, transaction_date, transaction_year, transaction_month,
                category_id, merchant_name, amount, institution_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''', (workspace2_id, '2025-01-15', 2025, 1, category_id, 'Restaurant B', 5000, institution_id))
        transaction_ws2_id = cursor.lastrowid

        db.commit()

        # User A marks transaction in Workspace 1 as allowance
        AllowanceTransactionRepository.mark_as_allowance(
            db,
            transaction_id=transaction_ws1_id,
            user_id=user1_id,
            workspace_id=workspace1_id
        )

        # Initialize repository
        txn_repo = TransactionRepository(db, cat_repo, inst_repo)

        # User B in Workspace 1 should NOT see the transaction
        ws1_transactions, ws1_count = txn_repo.get_filtered(
            workspace_id=workspace1_id,
            exclude_allowances_for_user_id=user2_id,
            year=2025,
            month=1
        )
        assert ws1_count == 0, "User B should not see User A's allowance in Workspace 1"

        # User B in Workspace 2 SHOULD see the transaction (not marked there)
        ws2_transactions, ws2_count = txn_repo.get_filtered(
            workspace_id=workspace2_id,
            exclude_allowances_for_user_id=user2_id,
            year=2025,
            month=1
        )
        assert ws2_count == 1, "User B should see transaction in Workspace 2 (not marked as allowance there)"
        assert ws2_transactions[0]['id'] == transaction_ws2_id, \
            "Should be the Workspace 2 transaction"


class TestAllowancePrivacyEdgeCases:
    """Test edge cases and boundary conditions."""

    def test_zero_allowances_does_not_break_queries(self, db_with_users_and_workspace):
        """
        Queries should work correctly when no allowances exist.
        """
        data = db_with_users_and_workspace
        db = data["db"]

        # Initialize repository
        cat_repo = CategoryRepository(db)
        inst_repo = InstitutionRepository(db)
        txn_repo = TransactionRepository(db, cat_repo, inst_repo)

        # Query with no allowances should return all transactions
        transactions, count = txn_repo.get_filtered(
            workspace_id=data["workspace_id"],
            exclude_allowances_for_user_id=data["user1_id"],
            year=2025,
            month=1
        )
        assert count == 2, "Should return all transactions when no allowances exist"

        # Total should include all transactions
        total = txn_repo.get_filtered_total_amount(
            workspace_id=data["workspace_id"],
            exclude_allowances_for_user_id=data["user1_id"],
            year=2025,
            month=1
        )
        assert total == 8000, "Total should include all transactions when no allowances exist"

    def test_all_transactions_marked_as_allowances(self, db_with_users_and_workspace):
        """
        When all transactions are marked as allowances, other users should see empty results.
        """
        data = db_with_users_and_workspace
        db = data["db"]

        # User A marks both transactions
        AllowanceTransactionRepository.mark_as_allowance(
            db,
            transaction_id=data["transaction1_id"],
            user_id=data["user1_id"],
            workspace_id=data["workspace_id"]
        )
        AllowanceTransactionRepository.mark_as_allowance(
            db,
            transaction_id=data["transaction2_id"],
            user_id=data["user1_id"],
            workspace_id=data["workspace_id"]
        )

        # Initialize repository
        cat_repo = CategoryRepository(db)
        inst_repo = InstitutionRepository(db)
        txn_repo = TransactionRepository(db, cat_repo, inst_repo)

        # User B should see no transactions
        transactions, count = txn_repo.get_filtered(
            workspace_id=data["workspace_id"],
            exclude_allowances_for_user_id=data["user2_id"],
            year=2025,
            month=1
        )
        assert count == 0, "User B should see no transactions when all marked as User A's allowances"

        # User B's total should be 0
        total = txn_repo.get_filtered_total_amount(
            workspace_id=data["workspace_id"],
            exclude_allowances_for_user_id=data["user2_id"],
            year=2025,
            month=1
        )
        assert total == 0, "User B's total should be 0 when all transactions are User A's allowances"

        # User A should still see both transactions
        user_a_transactions, user_a_count = txn_repo.get_filtered(
            workspace_id=data["workspace_id"],
            exclude_allowances_for_user_id=data["user1_id"],
            year=2025,
            month=1
        )
        assert user_a_count == 2, "User A should see all their own allowances"
