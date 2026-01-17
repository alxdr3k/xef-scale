class CreateCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :categories do |t|
      t.string :name
      t.string :keyword
      t.string :color
      t.references :workspace, null: false, foreign_key: true

      t.timestamps
    end
  end
end
