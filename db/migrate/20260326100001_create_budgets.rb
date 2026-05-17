class CreateBudgets < ActiveRecord::Migration[8.1]
  def change
    create_table :budgets do |t|
      t.references :workspace, null: false, foreign_key: true, index: { unique: true }
      t.integer :monthly_amount, null: false
      t.timestamps
    end
  end
end
