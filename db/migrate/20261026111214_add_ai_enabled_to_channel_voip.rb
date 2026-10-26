class AddAiEnabledToChannelVoip < ActiveRecord::Migration[7.2]
  def change
    add_column :channel_voip, :ai_enabled, :boolean, null: false, default: false
  end
end
