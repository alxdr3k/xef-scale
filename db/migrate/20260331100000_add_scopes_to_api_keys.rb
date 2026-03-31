class AddScopesToApiKeys < ActiveRecord::Migration[8.1]
  def change
    add_column :api_keys, :scopes, :string, default: "read", null: false
  end
end
