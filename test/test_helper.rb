require "simplecov"
SimpleCov.start "rails" do
  enable_coverage :branch

  add_filter "/test/"
  add_filter "/config/"
  add_filter "/vendor/"

  add_group "Models", "app/models"
  add_group "Controllers", "app/controllers"
  add_group "Services", "app/services"
  add_group "Jobs", "app/jobs"
  add_group "Helpers", "app/helpers"

  # Don't fail on low coverage during parallel tests
  minimum_coverage 0
end

# Configure parallel test merging
if ENV["PARALLEL_TEST_GROUPS"]
  SimpleCov.command_name "Minitest #{ENV['PARALLEL_TEST_GROUPS']}"
end

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Disable parallel tests for better SimpleCov coverage
    # parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

class ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
end
