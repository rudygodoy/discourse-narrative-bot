PLUGIN_NAME = "discourse-narrative-bot"

# TODO In the future, don't just hijack this guy.
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
        
    if (main_topic != nil)
      data[:topic_id] = main_topic.id
      dirty
    end

    if (data[:topic_id])
      reply get_user, dialogue('hello', binding)
    else
      copy = dialogue('welcome_topic_body', binding)
      data[:topic_id] = ( reply get_user, copy, {
          title: title, 
          category: Category.find_by(slug: 'staff').id
        }
      ).topic.id

      dirty

      reply get_user, dialogue('hello', binding)
    end

    :waiting_quote
  end

  state :waiting_quote, on: 'reply' do | user, post |
    if data[:topic_id] === post.topic.id
      copy = dialogue('quote_user', binding)
      reply get_user, copy
      :waiting_user_newtopic
    end
  end

  state :waiting_user_newtopic, on: 'reply' do | user, post |
    if post.topic.category.slug === 'staff' && (subject = (/((unicorn)|(bacon)|(ninja)|(monkey))/i.match(post.raw)).to_s) && post.topic.id != data[:topic_id]
      data[:topic_id] = post.topic.id
      dirty

      copy = dialogue('topic_bot_likes', binding)

      reply get_user, copy
      :duel
    end
  end

  state :duel, on: 'reply' do | user, post |
    return if data[:topic_id] != post.topic.id
    post.post_analyzer.cook post.raw, {}

    if post.post_analyzer.found_oneboxes?
      :end # TODO something else later? 
    else
      reply get_user, dialogue('no_onebox', binding)
    end
  end

  state :end do | user |
    reply get_user, dialogue('congratulations', binding)
  end
end