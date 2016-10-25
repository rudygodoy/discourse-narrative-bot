# name: discourse-narrative-bot
# about: Introduces staff to Discourse
# version: 0.0.1
# authors: Nick Sahler (@nicksahler)

require 'json'

enabled_site_setting :introbot_enabled

PLUGIN_NAME = "discourse-narrative-bot".freeze

after_initialize do
  SeedFu.fixture_paths << Rails.root.join("plugins", "discourse-narrative-bot", "db", "fixtures").to_s

  require_dependency 'application_controller'
  require_dependency 'discourse_event'
  require_dependency 'admin_constraint'
  require_dependency File.expand_path('../jobs/narrative_input.rb', __FILE__)


  load File.expand_path("../app/models/group_user.rb", __FILE__)
  load File.expand_path("../narrative.rb", __FILE__)

  # TODO Automatically load this folder in
  load File.expand_path("../narratives/staff_introduction/index.rb", __FILE__)

  module ::Narratives
    class Engine < ::Rails::Engine
      engine_name PLUGIN_NAME
      isolate_namespace Narratives
    end

    class NarrativesController < ::ApplicationController
      def reset
        ::PluginStore.set(PLUGIN_NAME, "narrative_#{params[:narrative]}_#{params[:user_id]}", nil)
        render :json, {}.to_s
      end

      def status
        render :json, ::PluginStore.get(PLUGIN_NAME, "narrative_#{params[:narrative]}_#{params[:user_id]}")
      end
    end
  end

  Narratives::Engine.routes.draw do
    get "/reset/:user_id/:narrative" => "narratives#reset", constraints: AdminConstraint.new
    get "/status/:user_id/:narrative" => "narratives#status", constraints: AdminConstraint.new
  end

  Discourse::Application.routes.prepend do
    mount ::Narratives::Engine, at: "/narratives"
  end
end
