class CreateBills < ActiveRecord::Migration[8.0]
  def change
    create_table :bills do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :project, null: false, foreign_key: true, index: true

      t.string :name, null: false

      t.timestamps
    end

    add_index :bills, [:account_id, :project_id]
  end
end

