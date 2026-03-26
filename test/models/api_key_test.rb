require "test_helper"

class ApiKeyTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:main_workspace)
  end

  test "generate creates a new API key with raw key" do
    api_key = ApiKey.generate(workspace: @workspace, name: "My Key")

    assert api_key.persisted?
    assert api_key.raw_key.present?
    assert api_key.raw_key.start_with?("xef_")
    assert_equal "My Key", api_key.name
    assert_equal @workspace, api_key.workspace
    assert_equal api_key.raw_key[0, 8], api_key.key_prefix
  end

  test "generate stores HMAC digest, not raw key" do
    api_key = ApiKey.generate(workspace: @workspace, name: "Test")

    expected_digest = OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, api_key.raw_key)
    assert_equal expected_digest, api_key.key_digest
  end

  test "authenticate returns key for valid token" do
    api_key = ApiKey.generate(workspace: @workspace, name: "Auth Test")
    raw_key = api_key.raw_key

    found = ApiKey.authenticate(raw_key)
    assert_equal api_key, found
  end

  test "authenticate returns nil for invalid token" do
    assert_nil ApiKey.authenticate("xef_invalid_token_that_does_not_exist")
  end

  test "authenticate returns nil for blank token" do
    assert_nil ApiKey.authenticate("")
    assert_nil ApiKey.authenticate(nil)
  end

  test "authenticate does not return revoked keys" do
    api_key = ApiKey.generate(workspace: @workspace, name: "Revoke Test")
    raw_key = api_key.raw_key
    api_key.revoke!

    assert_nil ApiKey.authenticate(raw_key)
  end

  test "authenticate touches last_used_at" do
    api_key = ApiKey.generate(workspace: @workspace, name: "Touch Test")
    assert_nil api_key.last_used_at

    ApiKey.authenticate(api_key.raw_key)
    api_key.reload

    assert_not_nil api_key.last_used_at
  end

  test "authenticate does not touch last_used_at if recently used" do
    api_key = ApiKey.generate(workspace: @workspace, name: "Recent Test")
    api_key.update_column(:last_used_at, 30.minutes.ago)
    old_time = api_key.last_used_at

    ApiKey.authenticate(api_key.raw_key)
    api_key.reload

    assert_equal old_time.to_i, api_key.last_used_at.to_i
  end

  test "revoke! sets revoked_at" do
    api_key = ApiKey.generate(workspace: @workspace, name: "Revoke")
    assert_not api_key.revoked?

    api_key.revoke!

    assert api_key.revoked?
    assert_not_nil api_key.revoked_at
  end

  test "key_digest must be unique" do
    first_key = ApiKey.generate(workspace: @workspace, name: "First")
    # Creating with same digest should fail
    assert_raises(ActiveRecord::RecordInvalid) do
      ApiKey.create!(
        workspace: @workspace,
        name: "Duplicate",
        key_digest: first_key.key_digest,
        key_prefix: "xef_dup"
      )
    end
  end
end
