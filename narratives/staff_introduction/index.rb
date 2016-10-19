PLUGIN_NAME = "discourse-narrative-bot"

# TODO In the future, don't just hijack this guy. Or maybe do. Are there consequences to this? 
def get_user
  @discobot ||= User.find_by({username: "discobot"})

  unless @discobot
    @discobot = User.create(
      name: "Discobot",
      username: "discobot",
      approved: true, active: true,
      admin: true,
      password: SecureRandom.hex,
      email: "#{SecureRandom.hex}@anon.#{Discourse.current_hostname}",
      trust_level: 4,
      trust_level_locked: true,
      created_at: 10000.years.ago
    )

    @discobot.grant_admin!
    @discobot.activate

    # TODO Pull the user avatar from that thread for now. In the future, pull it from a local file or from some central discobot repo.
    UserAvatar.import_url_for_user(
      "https://cdn.discourse.org/dev/uploads/default/original/2X/e/edb63d57a720838a7ce6a68f02ba4618787f2299.png",
      @discobot,
      override_gravatar: true )
  end
  @discobot
end

# TODO(@nicksahler) Move all of this to an event job
DiscourseEvent.on(:group_user_created) do | group_user |
  Jobs.enqueue(:narrative_input,
    user_id: group_user.user.id,
    narrative: 'staff_introduction',
    input: 'init'
  ) if group_user.group.name === 'staff' && group_user.user.id != get_user.id 
end

DiscourseEvent.on(:post_created) do | post |
  Jobs.enqueue(:narrative_input,
    user_id: post.user.id,
    post_id: post.id,
    narrative: 'staff_introduction',
    input: 'reply'
  )
end

# Staff intro here
# TODO Move to i18n, use that kind of interpolation.

Narrative.create 'staff_introduction' do
  state :begin, on: 'init' do | user |
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

  state :waiting_quote, on: 'reply' do | user, post |
    next unless data[:topic_id] === post.topic.id

    sleep(rand(3..5).seconds)
    reply get_user, dialogue('quote_user', binding)
    :tutorial_topic
  end

  state :next_tutorial do | user, post |
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
  state :tutorial_topic, on: 'reply' do | user, post |
    
    data[:topic_id] = post.topic.id
    data[:subject] = subject

    :next_tutorial
  end

  state :tutorial_onebox, on: 'reply' do | user, post |
    # TODO Before, the conditional applied before post_analyzer did its business. This was so it didn't analyze every post. Now, it's not the case - but in the future there will be a conditional at a higher level for posts made in new topics. I moved it down to clean up the code.
    post.post_analyzer.cook post.raw, {}
    :next_tutorial if data[:topic_id] == post.topic.id && post.post_analyzer.found_oneboxes?
  end

  state :tutorial_picture, on: 'reply' do | user, post |
    post.post_analyzer.cook post.raw, {}
    :next_tutorial if data[:topic_id] == post.topic.id && post.post_analyzer.image_count > 0
  end

  # TODO Maybe _hint_ at the user to use __both__ if they only use one? ? 
  # TODO Rid the cooking mess 
  state :tutorial_formatting, on: 'reply' do | user, post |
    processor = CookedPostProcessor.new(post)
    doc = Nokogiri::HTML.fragment(processor.html)
    :next_tutorial if data[:topic_id] == post.topic.id && doc.css("strong").size > 0 && (doc.css("em").size > 0 || doc.css("i").size > 0)
  end

  state :tutorial_quote, on: 'reply' do | user, post |
    processor = CookedPostProcessor.new(post)
    doc = Nokogiri::HTML.fragment(processor.html)
    :next_tutorial if data[:topic_id] == post.topic.id && doc.css(".quote").size > 0
  end

  state :tutorial_emoji, on: 'reply' do | user, post |
    processor = CookedPostProcessor.new(post)
    :next_tutorial if data[:topic_id] == post.topic.id && processor.has_emoji?
  end

  state :tutorial_mention, on: 'reply' do | user, post |
    :next_tutorial if data[:topic_id] == post.topic.id && post.raw.include?("@#{get_user.username}")
  end

  state :tutorial_link, on: 'reply' do | user, post |
    post.post_analyzer.cook post.raw, {}
    :next_tutorial if data[:topic_id] == post.topic.id && (post.post_analyzer.link_count() > 0)
  end

  # TODO broken, fix 
  state :tutorial_pm, on: 'reply' do | user, post |
    if post.archetype == Archetype.private_message && post.topic.all_allowed_users.any? { |p| p.id == get_user.id }
      reply get_user, dialogue('tutorial_pm_reply', binding), { topic_id: post.topic }
      :next_tutorial
    end
  end
end