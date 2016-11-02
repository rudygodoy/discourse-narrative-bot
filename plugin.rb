# name: discourse-narrative-bot
# about: Introduces staff to Discourse
# version: 0.0.1
# authors: Nick Sahler (@nicksahler)

enabled_site_setting :introbot_enabled

after_initialize do
  SeedFu.fixture_paths << Rails.root.join("plugins", "discourse-narrative-bot", "db", "fixtures").to_s

  require_dependency 'application_controller'
  require_dependency 'discourse_event'
  require_dependency 'admin_constraint'
  require_dependency File.expand_path('../jobs/new_user_narrative_input.rb', __FILE__)
  require_dependency File.expand_path('../jobs/new_user_narrative_timeout.rb', __FILE__)

  load File.expand_path("../lib/discourse_narrative_bot/new_user_narrative.rb", __FILE__)

  module ::DiscourseNarrativeBot
    PLUGIN_NAME = "discourse-narrative-bot".freeze

    class Engine < ::Rails::Engine
      engine_name PLUGIN_NAME
      isolate_namespace DiscourseNarrativeBot
    end

    class Store
      def self.set(user_id, value)
        ::PluginStore.set(PLUGIN_NAME, key(user_id), value)
      end

      def self.get(user_id)
        ::PluginStore.get(PLUGIN_NAME, key(user_id))
      end

      private

      def self.key(user_id)
        "narrative_state_#{user_id}"
      end
    end
  end

  self.add_model_callback(User, :after_destroy) do
    DiscourseNarrativeBot::Store.set(self.id, nil)
  end

  self.on(:user_created) do |user|
    if ![-1, -2].include?(user.id)
      Jobs.enqueue_in(15, :new_user_narrative_input,
        user_id: user.id,
        input: :init
      )
    end
  end

  self.on(:post_created) do |post|
    if ![-1, -2].include?(post.user.id)
      Jobs.enqueue(:new_user_narrative_input,
        user_id: post.user.id,
        post_id: post.id,
        input: :reply
      )
    end
  end
end
