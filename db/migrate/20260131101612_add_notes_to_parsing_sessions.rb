class AddNotesToParsingSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :parsing_sessions, :notes, :text
  end
end
