class AddSourceMetadataToTransactions < ActiveRecord::Migration[8.1]
  def change
    add_column :transactions, :source_metadata, :text
  end
end
