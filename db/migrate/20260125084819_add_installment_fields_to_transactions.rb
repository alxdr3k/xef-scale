class AddInstallmentFieldsToTransactions < ActiveRecord::Migration[8.1]
  def change
    add_column :transactions, :installment_month, :integer
    add_column :transactions, :installment_total, :integer
    add_column :transactions, :original_amount, :integer
    add_column :transactions, :benefit_type, :string
    add_column :transactions, :benefit_amount, :integer
  end
end
