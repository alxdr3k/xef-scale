require "test_helper"

class CategoryTest < ActiveSupport::TestCase
  test "category is valid with valid attributes" do
    category = categories(:food)
    assert category.valid?
  end

  test "category requires name" do
    category = Category.new(workspace: workspaces(:main_workspace))
    assert_not category.valid?
    assert_includes category.errors[:name], "can't be blank"
  end

  test "category name must be unique within workspace" do
    existing = categories(:food)
    category = Category.new(
      name: existing.name,
      workspace: existing.workspace
    )
    assert_not category.valid?
    assert_includes category.errors[:name], "has already been taken"
  end

  test "category name can be same in different workspaces" do
    category = Category.new(
      name: categories(:food).name,
      workspace: workspaces(:other_workspace)
    )
    assert category.valid?
  end

  test "keywords_array returns array of keywords" do
    category = categories(:food)
    keywords = category.keywords_array
    assert_includes keywords, '식당'
    assert_includes keywords, '마라탕'
  end

  test "keywords_array handles empty keyword" do
    category = categories(:etc)
    assert_equal [], category.keywords_array
  end

  test "matches? returns true when text contains keyword" do
    category = categories(:food)
    assert category.matches?('맛있는 마라탕집')
    assert category.matches?('식당에서 점심')
  end

  test "matches? returns false when text does not contain keyword" do
    category = categories(:food)
    assert_not category.matches?('택시 요금')
  end

  test "matches? is case insensitive" do
    category = categories(:transport)
    assert category.matches?('카카오T 택시')
    assert category.matches?('카카오t 이용')
  end

  test "matches? returns false for blank text" do
    category = categories(:food)
    assert_not category.matches?('')
    assert_not category.matches?(nil)
  end

  test "destroying category nullifies transaction category" do
    category = categories(:food)
    transaction = transactions(:food_transaction)

    category.destroy

    transaction.reload
    assert_nil transaction.category_id
  end
end
