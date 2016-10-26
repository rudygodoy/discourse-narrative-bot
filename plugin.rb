# name: discourse-narrative-bot
# about: Introduces staff to Discourse
# version: 0.0.1
# authors: Nick Sahler (@nicksahler)

require 'json'

enabled_site_setting :introbot_enabled

after_initialize do
  SeedFu.fixture_paths << Rails.root.join("plugins", "discourse-narrative-bot", "db", "fixtures").to_s

  require_dependency 'application_controller'
  require_dependency 'discourse_event'
  require_dependency 'admin_constraint'
  require_dependency File.expand_path('../jobs/narrative_input.rb', __FILE__)


  load File.expand_path("../app/models/group_user.rb", __FILE__)
  load File.expand_path("../lib/discourse_narrative_bot/narrative.rb", __FILE__)

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

    class NarrativesController < ::ApplicationController
      def reset
        ::DiscourseNarrativeBot::Store.set(params[:narrative], params[:user_id], nil)
        render :json, {}.to_s
      end

      def status
        render :json, ::DiscourseNarrativeBot::Store.get(params[:narrative], params[:user_id])
      end
    end
  end

  DiscourseNarrativeBot::Engine.routes.draw do
    get "/reset/:user_id/:narrative" => "narratives#reset", constraints: AdminConstraint.new
    get "/status/:user_id/:narrative" => "narratives#status", constraints: AdminConstraint.new
  end

  Discourse::Application.routes.prepend do
    mount ::DiscourseNarrativeBot::Engine, at: "/narratives"
  end

  DiscourseEvent.on(:group_user_created) do |group_user|
    if group_user.group.name === 'staff' && ![-1, -2].include?(group_user.user.id)
      Jobs.enqueue(:narrative_input,
        user_id: group_user.user.id,
        narrative: 'staff_introduction',
        input: 'init'
      )
    end
  end

  DiscourseEvent.on(:post_created) do |post|
    if ![-1, -2].include?(user = post.user.id)
      Jobs.enqueue(:narrative_input,
        user_id: post.user.id,
        post_id: post.id,
        narrative: 'staff_introduction',
        input: 'reply'
      )
    end
  end
end
