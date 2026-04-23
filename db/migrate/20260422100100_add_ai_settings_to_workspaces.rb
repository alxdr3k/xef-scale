class AddAiSettingsToWorkspaces < ActiveRecord::Migration[8.0]
  def change
    change_table :workspaces do |t|
      t.boolean :ai_text_parsing_enabled, default: true, null: false
      t.boolean :ai_image_parsing_enabled, default: true, null: false
      t.boolean :ai_category_suggestions_enabled, default: true, null: false
      t.datetime :ai_consent_acknowledged_at
    end
  end
end
