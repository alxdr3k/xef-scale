class AddPaymentTypeToTransactions < ActiveRecord::Migration[8.1]
  def change
    add_column :transactions, :payment_type, :string, default: "lump_sum", null: false
    add_index :transactions, :payment_type

    # Update existing records based on installment info
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE transactions
          SET payment_type = 'installment'
          WHERE installment_total IS NOT NULL AND installment_total > 1
        SQL
      end
    end
  end
end
