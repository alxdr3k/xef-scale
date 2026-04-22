require "test_helper"

class CategoryMappingTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:main_workspace)
    @category = categories(:food)
  end

  test "sync_dedup_signature derives signature from pattern fields" do
    mapping = CategoryMapping.new(
      workspace: @workspace,
      category: @category,
      merchant_pattern: "스타벅스강남점",
      description_pattern: nil,
      match_type: "exact",
      amount: nil,
      source: "manual"
    )
    mapping.valid?
    assert_equal "스타벅스강남점\x1F\x1Fexact\x1F", mapping.dedup_signature
  end

  test "two rows with nil amount and same pattern cannot coexist (NULL-amount race fix)" do
    CategoryMapping.create!(
      workspace: @workspace,
      category: @category,
      merchant_pattern: "스타벅스강남점",
      match_type: "exact",
      amount: nil,
      source: "manual"
    )

    duplicate = CategoryMapping.new(
      workspace: @workspace,
      category: @category,
      merchant_pattern: "스타벅스강남점",
      match_type: "exact",
      amount: nil,
      source: "gemini"
    )

    assert_not duplicate.valid?, "Rails-level uniqueness must reject nil-amount duplicates"
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save(validate: false) }
  end

  test "same pattern with different amounts is allowed" do
    CategoryMapping.create!(
      workspace: @workspace,
      category: @category,
      merchant_pattern: "편의점",
      match_type: "exact",
      amount: nil,
      source: "manual"
    )

    specific = CategoryMapping.new(
      workspace: @workspace,
      category: @category,
      merchant_pattern: "편의점",
      match_type: "exact",
      amount: 5000,
      source: "manual"
    )
    assert specific.valid?, specific.errors.full_messages.join(", ")
  end

  test "same pattern across different workspaces is allowed" do
    CategoryMapping.create!(
      workspace: @workspace,
      category: @category,
      merchant_pattern: "편의점",
      match_type: "exact",
      amount: nil,
      source: "manual"
    )

    other_workspace_mapping = CategoryMapping.new(
      workspace: workspaces(:other_workspace),
      category: categories(:other_category),
      merchant_pattern: "편의점",
      match_type: "exact",
      amount: nil,
      source: "manual"
    )
    assert other_workspace_mapping.valid?
  end
end
