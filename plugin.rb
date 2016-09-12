# name: discourse-narrative-bot
# about: Introduces staff to Discourse
# version: 0.0.1
# authors: Nick Sahler (@nicksahler)

require 'json'

enabled_site_setting :introbot_enabled

PLUGIN_NAME = "discourse-narrative-bot".freeze

after_initialize do
  load File.expand_path("../app/models/group_user.rb", __FILE__)
  load File.expand_path("../narrative.rb", __FILE__)
  load File.expand_path("../narratives/staff_intro.rb", __FILE__)


  module ::IntroBot
    class Engine < ::Rails::Engine
      engine_name PLUGIN_NAME
      isolate_namespace IntroBot
    end
  end

  require_dependency 'application_controller'
  require_dependency 'discourse_event'
  require_dependency 'admin_constraint'
end