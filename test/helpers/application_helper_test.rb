require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  # Create mock pagy objects for testing
  class MockPagy
    attr_accessor :pages, :prev, :next, :page

    def initialize(opts = {})
      @pages = opts[:pages] || 1
      @prev = opts[:prev]
      @next = opts[:next]
      @page = opts[:page] || 1
      @series_data = opts[:series] || [ 1 ]
    end

    def series
      @series_data
    end
  end

  test "pagy_nav returns empty string when pages is 1" do
    pagy = MockPagy.new(pages: 1)
    result = pagy_nav(pagy)
    assert_equal "", result
  end

  test "pagy_nav html structure" do
    # This test verifies the helper module has the pagy_nav method defined
    assert respond_to?(:pagy_nav)
  end
end
