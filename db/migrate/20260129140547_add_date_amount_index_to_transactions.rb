class AddDateAmountIndexToTransactions < ActiveRecord::Migration[8.1]
  def change
    add_index :transactions, [ :workspace_id, :date, :amount ], name: "index_transactions_on_workspace_date_amount"
  end
end
