class CreateTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :transactions do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :category, foreign_key: true
      t.references :financial_institution, foreign_key: true
      t.date :date, null: false
      t.string :description
      t.string :merchant
      t.integer :amount, null: false
      t.text :notes
      t.boolean :deleted, default: false

      t.timestamps
    end
    add_index :transactions, [ :workspace_id, :date ]
    add_index :transactions, [ :workspace_id, :category_id ]
    add_index :transactions, [ :date, :merchant, :amount ]
  end
end
