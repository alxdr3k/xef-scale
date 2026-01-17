class CreateWorkspaceInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :workspace_invitations do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :invited_by, null: false, foreign_key: { to_table: :users }
      t.string :token, null: false
      t.datetime :expires_at
      t.integer :max_uses
      t.integer :current_uses, default: 0

      t.timestamps
    end
    add_index :workspace_invitations, :token, unique: true
  end
end
