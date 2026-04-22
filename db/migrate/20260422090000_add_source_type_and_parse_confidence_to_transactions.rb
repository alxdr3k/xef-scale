class AddSourceTypeAndParseConfidenceToTransactions < ActiveRecord::Migration[8.1]
  def change
    add_column :transactions, :source_type, :string
    add_column :transactions, :parse_confidence, :decimal, precision: 4, scale: 3
    add_index :transactions, :source_type
  end
end
