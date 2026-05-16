class AddClassificationSourceToTransactions < ActiveRecord::Migration[8.1]
  # ADR-0011 — Transaction 단위 결정 메커니즘 보존 필드.
  # nullable, no default. 기존 거래는 백필하지 않는다 (정보 부족 → 추정 금지).
  # 호출지점에서 set하는 로직은 후속 PR.
  def change
    add_column :transactions, :classification_source, :string
    add_index :transactions, :classification_source
  end
end
