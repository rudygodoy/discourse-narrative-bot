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

  User.class_eval do
    after_commit :enqueue_new_user_narrative, on: :create

    private

    def enqueue_new_user_narrative
      if ![-1, -2].include?(self.id)
        Jobs.enqueue(:new_user_narrative_input,
          user_id: self.id,
          input: :init
        )
      end
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

  PostAction.class_eval do
    after_commit :enqueue_new_user_narrative, on: :create

    private

    def enqueue_new_user_narrative
      return true if [-1, -2].include?(self.user.id)

      input =
        case self.post_action_type_id
        when *PostActionType.flag_types.values
          :flag
        when PostActionType.types[:like]
          :like
        when PostActionType.types[:bookmark]
          :bookmark
        end

      if input
        Jobs.enqueue(:new_user_narrative_input,
          user_id: self.user.id,
          post_id: self.post.id,
          input: input
        )
      end
    end
  end
end
