# name: discourse-narrative-bot
# about: Introduces staff to Discourse
# version: 0.0.1
# authors: Nick Sahler (@nicksahler)

enabled_site_setting :discourse_narrative_bot_enabled

if Rails.env.development?
  Rails.application.config.before_initialize do |app|
    app.middleware.insert_before(
      ::ActionDispatch::Static,
      ::ActionDispatch::Static,
      Rails.root.join("plugins/discourse-narrative-bot/public").to_s
    )
  end
end

after_initialize do
  SeedFu.fixture_paths << Rails.root.join("plugins", "discourse-narrative-bot", "db", "fixtures").to_s

  Mime::Type.register "image/svg+xml", :svg

  load File.expand_path('../jobs/bot_input.rb', __FILE__)
  load File.expand_path('../jobs/narrative_timeout.rb', __FILE__)
  load File.expand_path('../jobs/narrative_init.rb', __FILE__)
  load File.expand_path('../jobs/onceoff/grant_badges.rb', __FILE__)
  load File.expand_path("../lib/discourse_narrative_bot/actions.rb", __FILE__)
  load File.expand_path("../lib/discourse_narrative_bot/base.rb", __FILE__)
  load File.expand_path("../lib/discourse_narrative_bot/new_user_narrative.rb", __FILE__)
  load File.expand_path("../lib/discourse_narrative_bot/advanced_user_narrative.rb", __FILE__)
  load File.expand_path("../lib/discourse_narrative_bot/track_selector.rb", __FILE__)
  load File.expand_path("../lib/discourse_narrative_bot/certificate_generator.rb", __FILE__)
  load File.expand_path("../lib/discourse_narrative_bot/dice.rb", __FILE__)
  load File.expand_path("../lib/discourse_narrative_bot/quote_generator.rb", __FILE__)
  load File.expand_path("../lib/discourse_narrative_bot/btc_price.rb", __FILE__)

  module ::DiscourseNarrativeBot
    PLUGIN_NAME = "discourse-narrative-bot".freeze

    class Engine < ::Rails::Engine
      engine_name PLUGIN_NAME
      isolate_namespace DiscourseNarrativeBot

      if Rails.env.production?
        Dir[Rails.root.join("plugins/discourse-narrative-bot/public/images/*")].each do |src|
          dest = Rails.root.join("public/images/#{File.basename(src)}")
          File.symlink(src, dest) if !File.exists?(dest)
        end
      end
    end

    class Store
      def self.set(key, value)
        ::PluginStore.set(PLUGIN_NAME, key, value)
      end

      def self.get(key)
        ::PluginStore.get(PLUGIN_NAME, key)
      end

      def self.remove(key)
        ::PluginStore.remove(PLUGIN_NAME, key)
      end
    end

    class CertificatesController < ::ApplicationController
      layout :false
      skip_before_filter :check_xhr

      def generate
        raise Discourse::InvalidParameters.new('user_id must be present') unless params[:user_id]&.present?

        user = User.find_by(id: params[:user_id])
        raise Discourse::NotFound if user.blank?

        raise Discourse::InvalidParameters.new('date must be present') unless params[:date]&.present?

        svg =
          case params[:type]
          when 'advanced'
            CertificateGenerator.advanced_user_track(user, params[:date])
          else
            CertificateGenerator.new_user_track(user, params[:date])
          end

        respond_to do |format|
          format.svg { render inline: svg}
        end
      end
    end
  end

  DiscourseNarrativeBot::Engine.routes.draw do
    get "/certificate" => "certificates#generate", format: :svg
  end

  Discourse::Application.routes.append do
    mount ::DiscourseNarrativeBot::Engine, at: "/discobot"
  end

  self.add_model_callback(User, :after_destroy) do
    DiscourseNarrativeBot::Store.remove(self.id)
  end

  self.add_model_callback(User, :after_commit, on: :create) do
    return if SiteSetting.disable_discourse_narrative_bot_welcome_post

    if enqueue_narrative_bot_job?
      Jobs.enqueue(:narrative_init,
        user_id: self.id,
        klass: DiscourseNarrativeBot::NewUserNarrative.to_s
      )
    end
  end

  require_dependency "user"

  User.class_eval do
    def enqueue_narrative_bot_job?
      SiteSetting.discourse_narrative_bot_enabled &&
        self.id > 0 &&
        !self.user_option.mailing_list_mode &&
        !self.staged &&
        !SiteSetting.discourse_narrative_bot_ignored_usernames.split('|'.freeze).include?(self.username)
    end
  end

  self.on(:post_created) do |post, options|
    user = post.user

    if user.enqueue_narrative_bot_job? && !options[:skip_bot]
      Jobs.enqueue(:bot_input,
        user_id: user.id,
        post_id: post.id,
        input: :reply
      )
    end
  end

  self.on(:post_edited) do |post|
    if post.user.enqueue_narrative_bot_job?
      Jobs.enqueue(:bot_input,
        user_id: post.user.id,
        post_id: post.id,
        input: :edit
      )
    end
  end

  self.on(:post_destroyed) do |post, options, user|
    if user.enqueue_narrative_bot_job? && !options[:skip_bot]
      Jobs.enqueue(:bot_input,
        user_id: user.id,
        post_id: post.id,
        topic_id: post.topic_id,
        input: :delete
      )
    end
  end

  self.on(:post_recovered) do |post, _, user|
    if user.enqueue_narrative_bot_job?
      Jobs.enqueue(:bot_input,
        user_id: user.id,
        post_id: post.id,
        input: :recover
      )
    end
  end

  self.add_model_callback(PostAction, :after_commit, on: :create) do
    if self.user.enqueue_narrative_bot_job?
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
        Jobs.enqueue(:bot_input,
          user_id: self.user.id,
          post_id: self.post.id,
          input: input
        )
      end
    end
  end

  self.on(:topic_notification_level_changed) do |_, user_id, topic_id|
    user = User.find_by(id: user_id)

    if user && user.enqueue_narrative_bot_job?
      Jobs.enqueue(:bot_input,
        user_id: user_id,
        topic_id: topic_id,
        input: :topic_notification_level_changed
      )
    end
  end

  should_send_welcome_message = SiteSetting.send_welcome_message

  if SiteSetting.discourse_narrative_bot_enabled
    SiteSetting.send_welcome_message = false
  end

  DiscourseEvent.on(:site_setting_saved) do |site_setting|
    if site_setting.name.to_s == 'discourse_narrative_bot_enabled'
      case site_setting.value
      when 'f'
        SiteSetting.send_welcome_message = should_send_welcome_message
      when 't'
        SiteSetting.send_welcome_message = false
      end
    end
  end

end
