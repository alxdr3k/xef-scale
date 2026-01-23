class CreateAllowanceTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :allowance_transactions do |t|
      t.references :expense_transaction, null: false, foreign_key: { to_table: :transactions }
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
    add_index :allowance_transactions, [ :expense_transaction_id, :user_id ], unique: true
  end
end
