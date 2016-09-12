# TODO Move to jobs 

# Temporary until pluginstore rows
@threads = Hash.new

PLUGIN_NAME = "discourse-narrative-bot"

# Temporary, move into narrative later.
def get_thread(user_id, narrative)
  
  n = Narrative.new narrative, ::PluginStore.get(PLUGIN_NAME, "narrative__#{user_id}") 
  n.on_data do | data |
    ::PluginStore.set(PLUGIN_NAME, "narrative__#{user_id}", data) 
    puts data;
  end
  n
end

DiscourseEvent.on(:group_user_created) do | group_user |
  if group_user.group.name === 'staff'
    narrative = get_thread group_user.user.id, 'staff_introduction'
    narrative.input 'init', group_user.group, group_user.user unless narrative.data[:topic_id]
  end
end

DiscourseEvent.on(:post_created) do | post |
  narrative = get_thread post.user.id, 'staff_introduction'
  narrative.input 'reply', post if narrative != nil
end

Narrative.create 'staff_introduction' do
  state :begin, on: 'init' do | group, user |
    post = PostCreator.create(
      Discourse.system_user,
      raw: "Hi @#{ user.username }. \n Welcome to your new Discourse install: #{SiteSetting.title}. I am a bot designed to teach you the basics of using Discourse effectively. To continue, click the reply button and say hello to me. You can mention users using the @ symbol like this: \n \"Hi @discoursebot!\".\n Tell me something directly and I'll say it back to you!",
      title: "Welcome, #{ user.username }!", 
      category: Category.find_by(slug: 'staff').id
    )

    data[:topic_id] = post.topic.id;
    dirty

    :waiting_quote
  end

  state :waiting_quote, on: 'reply' do | post |
    if data[:topic_id] === post.topic.id
      PostCreator.create( Discourse.system_user, raw: (I18n.t 'narratives.quote_user', username: post.user.username ), topic_id: data[:topic_id] )
      :waiting_user_quoted
    end
  end

  state :waiting_user_quoted, on: 'reply' do | post | 
    if data[:topic_id] === post.topic.id && /\[.*quote\s*=\s*"discoursebot/.match(post.raw)
      PostCreator.create( Discourse.system_user, raw: (I18n.t 'narratives.user_quoted'), topic_id: data[:topic_id])
      :waiting_image
    else
      PostCreator.create( Discourse.system_user, raw: (I18n.t 'narratives.user_quoted_fallback', username: post.user.username ), topic_id: data[:topic_id])
    end
  end
end