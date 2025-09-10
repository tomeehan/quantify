class CreatePackages < ActiveRecord::Migration[7.1]
  def change
    create_table :packages do |t|
      t.references :account, null: false, foreign_key: true
      t.references :bill, null: false, foreign_key: true
      t.string :name, null: false
      t.decimal :total_excl_vat, precision: 12, scale: 2

      t.timestamps
    end

    add_index :packages, [:account_id, :bill_id]
  end
end

