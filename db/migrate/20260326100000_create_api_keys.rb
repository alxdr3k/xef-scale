class CreateApiKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :api_keys do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string :name, null: false
      t.string :key_digest, null: false
      t.string :key_prefix, null: false, limit: 8
      t.datetime :last_used_at
      t.datetime :revoked_at
      t.timestamps
    end

    add_index :api_keys, :key_digest, unique: true
    add_index :api_keys, [ :workspace_id, :revoked_at ]
  end
end
