require "test_helper"

class WorkspaceTest < ActiveSupport::TestCase
  test "workspace is valid with valid attributes" do
    workspace = workspaces(:main_workspace)
    assert workspace.valid?
  end

  test "workspace requires name" do
    workspace = Workspace.new(owner: users(:admin))
    assert_not workspace.valid?
    assert_includes workspace.errors[:name], "can't be blank"
  end

  test "workspace belongs to owner" do
    workspace = workspaces(:main_workspace)
    assert_equal users(:admin), workspace.owner
  end

  test "workspace has many members through memberships" do
    workspace = workspaces(:main_workspace)
    assert_includes workspace.members, users(:admin)
    assert_includes workspace.members, users(:member)
    assert_includes workspace.members, users(:reader)
  end

  test "workspace has many categories" do
    workspace = workspaces(:main_workspace)
    assert_includes workspace.categories, categories(:food)
  end

  test "workspace has many transactions" do
    workspace = workspaces(:main_workspace)
    assert_includes workspace.transactions, transactions(:food_transaction)
  end

  test "destroying workspace destroys associated memberships" do
    workspace = Workspace.create!(name: "Test Workspace", owner: users(:admin))
    membership_count = workspace.workspace_memberships.count

    assert_difference "WorkspaceMembership.count", -membership_count do
      workspace.destroy
    end
  end

  test "creating workspace adds owner as member" do
    workspace = Workspace.create!(name: "New Workspace", owner: users(:admin))
    assert workspace.members.include?(users(:admin))
    membership = workspace.workspace_memberships.find_by(user: users(:admin))
    assert_equal "owner", membership.role
  end

  test "creating workspace creates default categories" do
    workspace = Workspace.create!(name: "New Workspace", owner: users(:admin))
    assert workspace.categories.exists?(name: "식비")
    assert workspace.categories.exists?(name: "편의점/마트")
    assert workspace.categories.exists?(name: "교통/자동차")
    assert workspace.categories.exists?(name: "주거/통신")
    assert workspace.categories.exists?(name: "쇼핑")
    assert workspace.categories.exists?(name: "문화/여가")
    assert workspace.categories.exists?(name: "의료/건강")
    assert workspace.categories.exists?(name: "보험")
    assert workspace.categories.exists?(name: "기타")
  end

  test "workspace has many invitations" do
    workspace = workspaces(:main_workspace)
    assert workspace.workspace_invitations.any?
  end

  test "workspace has many processed files" do
    workspace = workspaces(:main_workspace)
    assert workspace.processed_files.any?
  end

  test "workspace has many parsing sessions through processed files" do
    workspace = workspaces(:main_workspace)
    assert workspace.parsing_sessions.any?
  end

  test "destroying workspace destroys associated transactions" do
    workspace = Workspace.create!(name: "Test", owner: users(:admin))
    workspace.transactions.create!(date: Date.current, amount: 1000)

    assert_difference "Transaction.count", -1 do
      workspace.destroy
    end
  end

  test "ai_consent_required? is true until acknowledged when any AI feature is enabled" do
    workspace = Workspace.create!(name: "Consent", owner: users(:admin))
    assert workspace.ai_consent_required?, "fresh workspace defaults AI on so consent is needed"

    workspace.acknowledge_ai_consent!
    assert_not workspace.ai_consent_required?
  end

  test "ai_consent_required? is false when every AI feature is disabled" do
    workspace = Workspace.create!(
      name: "All off", owner: users(:admin),
      ai_text_parsing_enabled: false,
      ai_image_parsing_enabled: false,
      ai_category_suggestions_enabled: false
    )
    assert_not workspace.ai_consent_required?
  end
end
