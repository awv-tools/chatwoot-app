class AddCachedLabelsList < ActiveRecord::Migration[7.0]
  def change
    add_column :conversations, :cached_label_list, :string
    Conversation.reset_column_information
    # Older versions of acts-as-taggable-on exposed Taggable::Cache. Newer versions
    # may not define it. Guard to keep this migration compatible across versions.
    if defined?(ActsAsTaggableOn::Taggable::Cache) &&
       ActsAsTaggableOn::Taggable::Cache.respond_to?(:included)
      ActsAsTaggableOn::Taggable::Cache.included(Conversation)
    end
  end
end
