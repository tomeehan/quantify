class CreateLineItems < ActiveRecord::Migration[7.1]
  def change
    create_table :line_items do |t|
      t.references :account, null: false, foreign_key: true
      t.references :package, null: false, foreign_key: true

      t.string :item, null: false
      t.string :description

      t.integer :quantity, null: false, default: 0
      t.string :unit, null: false

      t.decimal :rate, precision: 12, scale: 2, default: 0
      t.decimal :markup, precision: 5, scale: 2, default: 0
      t.decimal :total, precision: 12, scale: 2, default: 0

      t.timestamps
    end

    add_index :line_items, [:account_id, :package_id]
  end
end

