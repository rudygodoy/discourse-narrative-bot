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
  Jobs.enqueue_in( rand(1..2).seconds, :narrative_input,
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
    data[:topic_id] = PostCreator.create(
      get_user,
      raw: %Q{Hi @#{ user.username }.
Welcome to your new Discourse install: #{SiteSetting.title}.
Reply to this post and I'll quote you!},
      title: "Welcome, #{ user.username }!", 
      category: Category.find_by(slug: 'staff').id
    ).topic.id

    dirty

    :waiting_quote
  end

  #(I18n.t 'narratives.quote_user', username: post.user.username )
  state :waiting_quote, on: 'reply' do | user, post |
    if data[:topic_id] === post.topic.id
      PostCreator.create( get_user, 
        raw: %Q{Great! If I remember correctly, you said:
[quote="#{post.user.username}, post:#{post.id}, topic:#{post.topic.id}, full:true"]
  #{post.raw}
[/quote]

Notice that new replies appear automatically, there's no need to refresh the page to get new information posted by other users.
Next, let's create a new post. Create a topic in the `staff` category and mention a subject I like, like **unicorns** or **bacon** or **ninjas** or **monkeys**!!!.},
        topic_id: data[:topic_id]
      )
      
      post.topic.update_status( :closed, true, get_user )
      :waiting_user_newtopic
    end
  end

  EXAMPLES = {
    "unicorn" => "Did you know that the unicorn is Scotland's national animal? :unicorn: \nhttps://en.wikipedia.org/wiki/Unicorn",
    "ninja" => "Did you know that ninjas used to hide in the same spot for days, disguised as inanimate objects like rocks and trees :leaves:? \nhttp://nerdreactor.com/wp-content/uploads/2012/12/Ninja_Gaiden_NES_02.jpg",
    "bacon" => ":pig: :pig: :pig: :pig: :pig: :pig: \nhttps://media.giphy.com/media/10l8MVei2OxbuU/giphy.gif \nhttps://media.giphy.com/media/qZiUOutzxgfKM/giphy.gif",
    "monkey" => ":monkey: :fries: \nhttps://www.youtube.com/watch?v=FjqfX8-L0Tk"
  }

  state :waiting_user_newtopic, on: 'reply' do | user, post |
    if post.topic.category.slug === 'staff' && (subject = /(unicorn(s))|(bacon)|(ninja(s))|(monkey(s))/i.match(post.raw))
      PostCreator.create(
        get_user,
        raw: "Omg, I love #{ subject.to_s }!!! \n #{EXAMPLES[subject.to_s.downcase.singularize]}",
        topic_id: post.topic.id
      )
      :end
    end
  end

end