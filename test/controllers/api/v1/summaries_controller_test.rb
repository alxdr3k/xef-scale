require "test_helper"

module Api
  module V1
    class SummariesControllerTest < ActionDispatch::IntegrationTest
      setup do
        @workspace = workspaces(:main_workspace)
        @api_key = ApiKey.generate(workspace: @workspace, name: "Test Key")
        @auth_header = { "Authorization" => "Bearer #{@api_key.raw_key}" }

        # Make transactions active
        @workspace.transactions.where(deleted: false).update_all(status: "committed")
      end

      test "monthly requires authentication" do
        get monthly_api_v1_summaries_path
        assert_response :unauthorized
      end

      test "monthly returns summary for current month" do
        get monthly_api_v1_summaries_path, headers: @auth_header
        assert_response :success

        json = JSON.parse(response.body)
        data = json["data"]

        assert_equal Date.current.year, data["year"]
        assert_equal Date.current.month, data["month"]
        assert data.key?("total_spending")
        assert data.key?("transaction_count")
        assert data.key?("daily_average")
        assert data.key?("category_breakdown")
        assert data["category_breakdown"].is_a?(Array)
      end

      test "monthly accepts year and month params" do
        get monthly_api_v1_summaries_path, headers: @auth_header, params: { year: 2025, month: 6 }
        assert_response :success

        json = JSON.parse(response.body)
        assert_equal 2025, json["data"]["year"]
        assert_equal 6, json["data"]["month"]
      end

      test "monthly category breakdown has correct structure" do
        get monthly_api_v1_summaries_path, headers: @auth_header
        assert_response :success

        json = JSON.parse(response.body)
        json["data"]["category_breakdown"].each do |cat|
          assert cat.key?("category")
          assert cat.key?("amount")
          assert cat.key?("count")
        end
      end

      test "yearly requires authentication" do
        get yearly_api_v1_summaries_path
        assert_response :unauthorized
      end

      test "yearly returns summary for current year" do
        get yearly_api_v1_summaries_path, headers: @auth_header
        assert_response :success

        json = JSON.parse(response.body)
        data = json["data"]

        assert_equal Date.current.year, data["year"]
        assert data.key?("total_spending")
        assert data.key?("monthly_average")
        assert data.key?("months")
        assert data["months"].is_a?(Array)
      end

      test "yearly accepts year param" do
        get yearly_api_v1_summaries_path, headers: @auth_header, params: { year: 2024 }
        assert_response :success

        json = JSON.parse(response.body)
        assert_equal 2024, json["data"]["year"]
      end

      test "yearly months have correct structure" do
        get yearly_api_v1_summaries_path, headers: @auth_header
        assert_response :success

        json = JSON.parse(response.body)
        json["data"]["months"].each do |m|
          assert m.key?("month")
          assert m.key?("total")
          assert m.key?("count")
        end
      end
    end
  end
end
