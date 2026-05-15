class AddDiscardedAtToParsingSessions < ActiveRecord::Migration[8.1]
  def up
    add_column :parsing_sessions, :discarded_at, :datetime

    # Backfill: existing discarded sessions have no dedicated timestamp, so the
    # best stable approximation is updated_at at backfill time. From this point
    # on, discard_all! writes discarded_at directly and later unrelated edits
    # (e.g. notes via inline_update) no longer drift the retention window.
    execute <<~SQL
      UPDATE parsing_sessions
      SET discarded_at = updated_at
      WHERE review_status = 'discarded'
        AND discarded_at IS NULL
    SQL
  end

  def down
    remove_column :parsing_sessions, :discarded_at
  end
end
