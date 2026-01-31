class CreateComments < ActiveRecord::Migration[8.1]
  def change
    create_table :comments do |t|
      t.references :transaction, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :body, null: false
      t.datetime :edited_at

      t.timestamps
    end

    add_column :transactions, :comments_count, :integer, default: 0, null: false
  end
end
