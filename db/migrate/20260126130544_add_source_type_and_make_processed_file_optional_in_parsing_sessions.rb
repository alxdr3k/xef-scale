class AddSourceTypeAndMakeProcessedFileOptionalInParsingSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :parsing_sessions, :source_type, :string, default: "file_upload"
    change_column_null :parsing_sessions, :processed_file_id, true
  end
end
