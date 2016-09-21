# TODO Move to jobs 

PLUGIN_NAME = "discourse-narrative-bot"
USER = Discourse.system_user

# TODO(@nicksahler) Move all of this to an event job
DiscourseEvent.on(:group_user_created) do | group_user |
  Jobs.enqueue(:narrative_input,
    user_id: group_user.user.id,
    narrative: 'staff_introduction',
    input: 'init'
  ) if group_user.group.name === 'staff'
end

DiscourseEvent.on(:post_created) do | post |
  Jobs.enqueue_in( rand(2..4).seconds, :narrative_input,
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
      USER,
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
      PostCreator.create( USER, 
        raw: %Q{Great! If I remember correctly, you said:
[quote="#{post.user.username}, post:#{post.id}, topic:#{post.topic.id}, full:true"]
  #{post.raw}
[/quote]

Notice that new replies appear automatically, there's no need to refresh the page to get new information posted by other users.
Next, let's create a new post. Create a topic in the `staff` category and mention me (@system).},
        topic_id: data[:topic_id]
      )
      
      post.topic.update_status( :closed, true, USER )
      :waiting_user_newtopic
    end
  end

  EXAMPLES = ["https://meta.discourse.org/t/congratulations-most-stars-in-2013-github-octoverse/12483", "http://en.wikipedia.org/wiki/Ruby_on_Rails", "http://www.amazon.com/Apple-MacBook-MGX72LL-13-3-Inch-Display/dp/B0096VDM8G", "https://twitter.com/discourse/status/500399710377484288", "https://itunes.apple.com/us/app/duke-nukem-manhattan-project/id663811684?mt=8", "https://soundcloud.com/neilcic/mouthsilence", "http://stackoverflow.com/questions/25427024/what-is-the-used-for-in-ruby", "https://github.com/discourse/discourse/pull/2561", "https://github.com/rack/rack/blob/master/lib/rack/etag.rb", "http://www.flickr.com/photos/eho/149282456/", "http://imgur.com/gallery/1PGTI", "http://thenextweb.com/au/2012/11/18/kim-dotcoms-plan-to-give-new-zealanders-free-internet-could-just-work/?fromcat=au", "http://www.youtube.com/watch?v=9bZkp7q19f0", "http://vimeo.com/channels/staffpicks/97765630", "http://www.funnyordie.com/videos/05c8ec50ed/between-two-ferns-with-zach-galifianakis-richard-branson", "http://techcrunch.com/2013/02/05/jeff-atwood-launches-discourse/"]
  wrap = proc { |a| "- `#{a}`\n"}

  state :waiting_user_newtopic, on: 'reply' do | user, post |
    # Better way to do this other than PostAlerter? 
    if data[:topic_id] != post.topic.id && post.raw.include?("@#{USER.username}")
      data[:topic_id] = post.topic.id
      dirty

      PostCreator.create(
        USER,
        raw: %Q{Great! Next let's have a conversation.
One great feature of Discourse is called OneBoxing. OneBoxing is when content from links is expanded and a useful summary is displayed, like this:
https://en.wikipedia.org/wiki/Cat

Reply here with some links you find interesting to check out OneBoxing!
If you need some ideas, feel free to ask for `help`!},
        topic_id: data[:topic_id])

      :duel
    end
  end

  state :duel, on: 'reply' do | user, post |
    return if data[:topic_id] != post.topic.id

    post.post_analyzer.cook post.raw, {}

    if post.post_analyzer.found_oneboxes?
      PostCreator.create(USER, raw: "Nice onebox thing! Here's something I found: \n#{ EXAMPLES.sample }", topic_id: data[:topic_id])
    else
      PostCreator.create(USER, raw: "That does not have a onebox in it! If you need some inspiration, here are some links you can paste: \n\n#{ EXAMPLES.map(&wrap).join('') }\n #{ post.post_analyzer.inspect }", topic_id: data[:topic_id])
    end
  end

  state :waiting_user_quoted, on: 'reply' do | user, post |
    if data[:topic_id] === post.topic.id && /\[.*quote\s*=\s*"discoursebot/.match(post.raw)
      PostCreator.create( USER, raw: (I18n.t 'narratives.user_quoted'), topic_id: data[:topic_id])
      :waiting_image
    else
      PostCreator.create( USER, raw: (I18n.t 'narratives.user_quoted_fallback', username: post.user.username ), topic_id: data[:topic_id])
    end
  end
end