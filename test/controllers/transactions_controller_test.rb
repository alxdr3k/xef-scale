require "test_helper"

class TransactionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:admin)
    @workspace = workspaces(:main_workspace)
    @transaction = transactions(:food_transaction)
    sign_in @user
  end

  test "index requires authentication" do
    sign_out @user
    get workspace_transactions_path(@workspace)
    assert_redirected_to new_user_session_path
  end

  test "index lists transactions" do
    get workspace_transactions_path(@workspace)
    assert_response :success
  end

  test "index filters by year" do
    get workspace_transactions_path(@workspace, year: Date.today.year)
    assert_response :success
  end

  test "index filters by month" do
    get workspace_transactions_path(@workspace, year: Date.today.year, month: Date.today.month)
    assert_response :success
  end

  test "index filters by category" do
    get workspace_transactions_path(@workspace, category_id: categories(:food).id)
    assert_response :success
  end

  test "index filters by institution" do
    get workspace_transactions_path(@workspace, institution_id: financial_institutions(:shinhan_card).id)
    assert_response :success
  end

  test "index searches by query" do
    get workspace_transactions_path(@workspace, q: "마라탕")
    assert_response :success
  end

  test "index ignores out-of-range month instead of crashing" do
    get workspace_transactions_path(@workspace, year: Date.current.year, month: 13)
    assert_response :success
  end

  test "index ignores non-numeric month instead of crashing" do
    get workspace_transactions_path(@workspace, year: Date.current.year, month: "abc")
    assert_response :success
  end

  test "index ignores out-of-range year instead of crashing" do
    get workspace_transactions_path(@workspace, year: 0, month: 1)
    assert_response :success
  end

  test "export ignores out-of-range month instead of crashing" do
    get export_workspace_transactions_path(@workspace, format: :csv, year: Date.current.year, month: 13)
    assert_response :success
  end

  test "new displays form" do
    get new_workspace_transaction_path(@workspace)
    assert_response :success
  end

  test "create creates transaction" do
    assert_difference "Transaction.count" do
      post workspace_transactions_path(@workspace), params: {
        transaction: {
          date: Date.today,
          merchant: "Test Merchant",
          amount: 10000,
          category_id: categories(:food).id
        }
      }
    end
    assert_redirected_to workspace_transactions_path(@workspace)
    assert_equal "manual", Transaction.last.source_type
  end

  test "create fails with invalid params" do
    assert_no_difference "Transaction.count" do
      post workspace_transactions_path(@workspace), params: {
        transaction: { date: "", amount: "" }
      }
    end
    assert_response :unprocessable_entity
  end

  test "edit displays form" do
    get edit_workspace_transaction_path(@workspace, @transaction)
    assert_response :success
  end

  test "update updates transaction" do
    patch workspace_transaction_path(@workspace, @transaction), params: {
      transaction: { merchant: "Updated Merchant" }
    }
    assert_redirected_to workspace_transactions_path(@workspace)
    assert_equal "Updated Merchant", @transaction.reload.merchant
  end

  test "destroy soft deletes transaction" do
    delete workspace_transaction_path(@workspace, @transaction)
    assert_redirected_to workspace_transactions_path(@workspace)
    assert @transaction.reload.deleted
  end

  test "toggle_allowance marks as allowance" do
    post toggle_allowance_workspace_transaction_path(@workspace, @transaction)
    assert_redirected_to workspace_transactions_path(@workspace)
  end

  test "toggle_allowance removes allowance" do
    AllowanceTransaction.create!(expense_transaction: @transaction, user: @user)
    post toggle_allowance_workspace_transaction_path(@workspace, @transaction)
    assert_redirected_to workspace_transactions_path(@workspace)
  end

  test "reader cannot create transaction" do
    sign_out @user
    sign_in users(:reader)
    assert_no_difference "Transaction.count" do
      post workspace_transactions_path(@workspace), params: {
        transaction: { date: Date.today, merchant: "Test", amount: 1000 }
      }
    end
    assert_redirected_to workspace_path(@workspace)
  end


  test "export generates csv" do
    get export_workspace_transactions_path(@workspace, format: :csv)
    assert_response :success
    assert_equal "text/csv; charset=utf-8", response.content_type
  end

  test "export filters by year" do
    get export_workspace_transactions_path(@workspace, format: :csv, year: Date.current.year)
    assert_response :success
  end

  test "export filters by year and month" do
    get export_workspace_transactions_path(@workspace, format: :csv, year: Date.current.year, month: Date.current.month)
    assert_response :success
  end


  test "update with invalid params renders edit" do
    patch workspace_transaction_path(@workspace, @transaction), params: {
      transaction: { date: "", amount: "" }
    }
    assert_response :unprocessable_entity
  end

  test "reader cannot edit transaction" do
    sign_out @user
    sign_in users(:reader)
    get edit_workspace_transaction_path(@workspace, @transaction)
    assert_redirected_to workspace_path(@workspace)
  end

  test "reader cannot update transaction" do
    sign_out @user
    sign_in users(:reader)
    patch workspace_transaction_path(@workspace, @transaction), params: {
      transaction: { merchant: "Updated" }
    }
    assert_redirected_to workspace_path(@workspace)
  end

  test "reader cannot delete transaction" do
    sign_out @user
    sign_in users(:reader)
    delete workspace_transaction_path(@workspace, @transaction)
    assert_redirected_to workspace_path(@workspace)
    assert_not @transaction.reload.deleted
  end

  test "index without year filters" do
    get workspace_transactions_path(@workspace, year: nil, month: nil)
    assert_response :success
  end
end
