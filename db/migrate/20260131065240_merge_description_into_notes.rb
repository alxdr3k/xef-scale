class MergeDescriptionIntoNotes < ActiveRecord::Migration[8.1]
  def up
    # description이 merchant와 다르고 notes가 비어있는 경우 → notes로 이동
    execute <<~SQL
      UPDATE transactions
      SET notes = description
      WHERE description IS NOT NULL
        AND description != merchant
        AND (notes IS NULL OR notes = '')
    SQL

    # description이 merchant와 다르고 notes도 있는 경우 → notes 앞에 추가
    execute <<~SQL
      UPDATE transactions
      SET notes = description || X'0A' || notes
      WHERE description IS NOT NULL
        AND description != merchant
        AND notes IS NOT NULL
        AND notes != ''
    SQL
  end

  def down
    # 되돌릴 수 없음 (데이터 손실 방지를 위해 description 컬럼은 유지)
  end
end
