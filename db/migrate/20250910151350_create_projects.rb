class CreateProjects < ActiveRecord::Migration[7.1]
  def change
    create_table :projects do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.string :address
      t.integer :square_footage
      t.integer :project_type, null: false, default: 0

      t.timestamps
    end

    add_index :projects, [:account_id, :name]
  end
end

