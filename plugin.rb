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
  load File.expand_path("../lib/discourse_narrative_bot/narrative.rb", __FILE__)

  module ::DiscourseNarrativeBot
    class Engine < ::Rails::Engine
      engine_name PLUGIN_NAME
      isolate_namespace DiscourseNarrativeBot
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

  DiscourseNarrativeBot::Engine.routes.draw do
    get "/reset/:user_id/:narrative" => "narratives#reset", constraints: AdminConstraint.new
    get "/status/:user_id/:narrative" => "narratives#status", constraints: AdminConstraint.new
  end

  Discourse::Application.routes.prepend do
    mount ::DiscourseNarrativeBot::Engine, at: "/narratives"
  end

  DiscourseEvent.on(:group_user_created) do |group_user|
    Jobs.enqueue(:narrative_input,
      user_id: group_user.user.id,
      narrative: 'staff_introduction',
      input: 'init'
    ) if group_user.group.name === 'staff' && group_user.user.id != get_user.id
  end

  DiscourseEvent.on(:post_created) do |post|
    Jobs.enqueue(:narrative_input,
      user_id: post.user.id,
      post_id: post.id,
      narrative: 'staff_introduction',
      input: 'reply'
    )
  end

  Narrative.create 'staff_introduction' do
    state :begin, on: 'init' do |user|
      title = dialogue('welcome_topic_title', binding)
      main_topic = Topic.find_by({slug: Slug.for(title)})

      data[:missions] = [:tutorial_onebox, :tutorial_picture, :tutorial_formatting, :tutorial_quote, :tutorial_emoji, :tutorial_mention, :tutorial_link, :tutorial_pm]

      if (main_topic != nil)
        data[:topic_id] = main_topic.id
      end

      if (data[:topic_id])
        reply get_user, dialogue('hello', binding)
      else
        data[:topic_id] = ( reply get_user, dialogue('welcome_topic_body', binding), {
            title: title,
            category: Category.find_by(slug: 'staff').id
          }
        ).topic.id

        reply get_user, dialogue('hello', binding)
      end

      :waiting_quote
    end

    state :waiting_quote, on: 'reply' do |user, post|
      next unless data[:topic_id] == post.topic.id

      sleep(rand(3..5).seconds)
      reply get_user, dialogue('quote_user', binding)
      :tutorial_topic
    end

    state :next_tutorial do |user, post|
      data[:missions].delete(data[:previous])
      next_mission = data[:missions].sample || :congratulations

      dialogue_previous_ending = dialogue( data[:previous].to_s.concat("_ok"), binding )
      dialogue_next_mission = dialogue( next_mission.to_s, binding )

      sleep(rand(2..3).seconds)
      PostAction.act(get_user, post, PostActionType.types[:like])
      reply get_user, "#{dialogue_previous_ending}\n#{dialogue_next_mission}"

      go next_mission
    end

    # Category is "staff" and subject has a fun topic and it's a new topic
    state :tutorial_topic, on: 'reply' do |user, post|

      data[:topic_id] = post.topic.id
      data[:subject] = subject

      :next_tutorial
    end

    state :tutorial_onebox, on: 'reply' do |user, post|
      # TODO Before, the conditional applied before post_analyzer did its business. This was so it didn't analyze every post. Now, it's not the case - but in the future there will be a conditional at a higher level for posts made in new topics. I moved it down to clean up the code.
      post.post_analyzer.cook post.raw, {}
      :next_tutorial if data[:topic_id] == post.topic.id && post.post_analyzer.found_oneboxes?
    end

    state :tutorial_picture, on: 'reply' do |user, post|
      post.post_analyzer.cook post.raw, {}
      :next_tutorial if data[:topic_id] == post.topic.id && post.post_analyzer.image_count > 0
    end

    # TODO Maybe _hint_ at the user to use __both__ if they only use one? ?
    # TODO Rid the cooking mess
    state :tutorial_formatting, on: 'reply' do |user, post|
      processor = CookedPostProcessor.new(post)
      doc = Nokogiri::HTML.fragment(processor.html)
      :next_tutorial if data[:topic_id] == post.topic.id && doc.css("strong").size > 0 && (doc.css("em").size > 0 || doc.css("i").size > 0)
    end

    state :tutorial_quote, on: 'reply' do |user, post|
      processor = CookedPostProcessor.new(post)
      doc = Nokogiri::HTML.fragment(processor.html)
      :next_tutorial if data[:topic_id] == post.topic.id && doc.css(".quote").size > 0
    end

    state :tutorial_emoji, on: 'reply' do |user, post|
      processor = CookedPostProcessor.new(post)
      :next_tutorial if data[:topic_id] == post.topic.id && processor.has_emoji?
    end

    state :tutorial_mention, on: 'reply' do |user, post|
      :next_tutorial if data[:topic_id] == post.topic.id && post.raw.include?("@#{get_user.username}")
    end

    state :tutorial_link, on: 'reply' do |user, post|
      post.post_analyzer.cook post.raw, {}
      :next_tutorial if data[:topic_id] == post.topic.id && (post.post_analyzer.link_count() > 0)
    end

    # TODO broken, fix
    state :tutorial_pm, on: 'reply' do |user, post|
      if post.archetype == Archetype.private_message && post.topic.all_allowed_users.any? { |p| p.id == get_user.id }
        reply get_user, dialogue('tutorial_pm_reply', binding), { topic_id: post.topic }
        :next_tutorial
      end
    end
  end
end
