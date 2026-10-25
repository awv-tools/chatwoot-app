class CreateChannelVoip < ActiveRecord::Migration[7.2]
  def change
    create_table :channel_voip do |t|
      t.integer :account_id, null: false
      t.string :phone_number, null: false
      t.string :line_id, null: false
      t.string :webhook_secret, null: false

      t.timestamps
    end

    add_index :channel_voip, :phone_number, unique: true
    add_index :channel_voip, :line_id, unique: true
  end
end
