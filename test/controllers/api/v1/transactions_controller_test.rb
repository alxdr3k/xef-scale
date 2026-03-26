require "test_helper"

module Api
  module V1
    class TransactionsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @workspace = workspaces(:main_workspace)
        @api_key = ApiKey.generate(workspace: @workspace, name: "Test Key")
        @auth_header = { "Authorization" => "Bearer #{@api_key.raw_key}" }

        # Make some transactions active (committed)
        @workspace.transactions.where(deleted: false).update_all(status: "committed")
      end

      test "index returns unauthorized without API key" do
        get api_v1_transactions_path
        assert_response :unauthorized
      end

      test "index returns unauthorized with invalid API key" do
        get api_v1_transactions_path, headers: { "Authorization" => "Bearer xef_invalid_key" }
        assert_response :unauthorized
      end

      test "index returns transactions with valid API key" do
        get api_v1_transactions_path, headers: @auth_header
        assert_response :success

        json = JSON.parse(response.body)
        assert json.key?("data")
        assert json.key?("meta")
        assert json["meta"]["total"].is_a?(Integer)
        assert json["meta"]["page"].is_a?(Integer)
      end

      test "index paginates results" do
        get api_v1_transactions_path, headers: @auth_header, params: { page: 1, per_page: 2 }
        assert_response :success

        json = JSON.parse(response.body)
        assert_equal 1, json["meta"]["page"]
        assert_equal 2, json["meta"]["per_page"]
        assert json["data"].length <= 2
      end

      test "index clamps per_page to valid range" do
        get api_v1_transactions_path, headers: @auth_header, params: { per_page: 0 }
        assert_response :success
        json = JSON.parse(response.body)
        assert_equal 1, json["meta"]["per_page"]

        get api_v1_transactions_path, headers: @auth_header, params: { per_page: 999 }
        assert_response :success
        json = JSON.parse(response.body)
        assert_equal 100, json["meta"]["per_page"]
      end

      test "index clamps page to minimum 1" do
        get api_v1_transactions_path, headers: @auth_header, params: { page: -5 }
        assert_response :success
        json = JSON.parse(response.body)
        assert_equal 1, json["meta"]["page"]
      end

      test "index filters by year" do
        get api_v1_transactions_path, headers: @auth_header, params: { year: Date.current.year }
        assert_response :success
      end

      test "index filters by category_id" do
        category = categories(:food)
        get api_v1_transactions_path, headers: @auth_header, params: { category_id: category.id }
        assert_response :success

        json = JSON.parse(response.body)
        json["data"].each do |tx|
          assert_equal category.id, tx["category_id"]
        end
      end

      test "index filters by search query" do
        get api_v1_transactions_path, headers: @auth_header, params: { q: "마라탕" }
        assert_response :success
      end

      test "index serializes transaction fields correctly" do
        get api_v1_transactions_path, headers: @auth_header
        assert_response :success

        json = JSON.parse(response.body)
        return unless json["data"].any?

        tx = json["data"].first
        assert tx.key?("id")
        assert tx.key?("date")
        assert tx.key?("merchant")
        assert tx.key?("amount")
        assert tx.key?("category")
        assert tx.key?("category_id")
        assert tx.key?("institution")
        assert tx.key?("institution_id")
        assert tx.key?("payment_type")
        assert tx.key?("notes")
        assert tx.key?("created_at")
      end

      test "index does not return other workspace transactions" do
        get api_v1_transactions_path, headers: @auth_header
        assert_response :success

        json = JSON.parse(response.body)
        other_tx = transactions(:other_workspace_transaction)
        ids = json["data"].map { |t| t["id"] }
        assert_not_includes ids, other_tx.id
      end

      test "show returns a single transaction" do
        tx = transactions(:food_transaction)
        tx.update_column(:status, "committed")

        get api_v1_transaction_path(tx), headers: @auth_header
        assert_response :success

        json = JSON.parse(response.body)
        assert_equal tx.id, json["data"]["id"]
      end

      test "show returns 404 for nonexistent transaction" do
        get api_v1_transaction_path(id: 999999), headers: @auth_header
        assert_response :not_found
      end

      test "show returns 404 for other workspace transaction" do
        other_tx = transactions(:other_workspace_transaction)
        other_tx.update_column(:status, "committed")

        get api_v1_transaction_path(other_tx), headers: @auth_header
        assert_response :not_found
      end
    end
  end
end
