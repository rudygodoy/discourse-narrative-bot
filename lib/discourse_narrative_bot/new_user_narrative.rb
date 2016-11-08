require_relative '../dice'
require_relative '../quote_generator'
require 'distributed_mutex'

module DiscourseNarrativeBot
  class NewUserNarrative
    TRANSITION_TABLE = {
      [:begin, :init] => {
        next_state: :waiting_reply,
        action: :say_hello
      },

      [:begin, :reply] => {
        next_state: :waiting_reply,
        action: :say_hello
      },

      [:waiting_reply, :reply] => {
        next_state: :tutorial_bookmark,
        next_instructions_key: 'bookmark.instructions',
        action: :react_to_reply
      },

      [:tutorial_bookmark, :bookmark] => {
        next_state: :tutorial_onebox,
        next_instructions_key: 'onebox.instructions',
        action: :reply_to_bookmark
      },

      [:tutorial_onebox, :reply] => {
        next_state: :tutorial_images,
        next_instructions_key: 'images.instructions',
        action: :reply_to_onebox
      },

      [:tutorial_images, :reply] => {
        next_state: :tutorial_formatting,
        next_instructions_key: 'formatting.instructions',
        action: :reply_to_image
      },

      [:tutorial_images, :like] => {
        next_state: :tutorial_formatting,
        next_instructions_key: 'formatting.instructions',
        action: :track_like
      },

      [:tutorial_formatting, :reply] => {
        next_state: :tutorial_quote,
        next_instructions_key: 'quoting.instructions',
        action: :reply_to_formatting
      },

      [:tutorial_quote, :reply] => {
        next_state: :tutorial_emoji,
        next_instructions_key: 'emoji.instructions',
        action: :reply_to_quote
      },

      [:tutorial_emoji, :reply] => {
        next_state: :tutorial_mention,
        next_instructions_key: 'mention.instructions',
        action: :reply_to_emoji
      },

      [:tutorial_mention, :reply] => {
        next_state: :tutorial_flag,
        next_instructions_key: 'flag.instructions',
        action: :reply_to_mention
      },

      [:tutorial_flag, :flag] => {
        next_state: :tutorial_link,
        next_instructions_key: 'link.instructions',
        action: :reply_to_flag
      },

      [:tutorial_link, :reply] => {
        next_state: :tutorial_search,
        next_instructions_key: 'search.instructions',
        action: :reply_to_link
      },

      [:tutorial_search, :reply] => {
        next_state: :end,
        action: :reply_to_search
      }
    }

    RESET_TRIGGER = 'please reset'.freeze
    SEARCH_ANSWER = ':rabbit:'.freeze
    DICE_TRIGGER = 'roll'.freeze
    TIMEOUT_DURATION = 900 # 15 mins

    class InvalidTransitionError < StandardError; end
    class DoNotUnderstandError < StandardError; end
    class TransitionError < StandardError; end

    def input(input, user, post)
      DistributedMutex.synchronize("new_user_narrative_#{user.id}") do
        @data = DiscourseNarrativeBot::Store.get(user.id) || {}
        @state = (@data[:state] && @data[:state].to_sym) || :begin
        @input = input
        @user = user
        @post = post
        opts = {}

        return if reset_bot?

        begin
          opts = transition
        rescue DoNotUnderstandError
          generic_replies
          return
        rescue TransitionError
          mention_replies
          return
        rescue InvalidTransitionError
          # For given input, no transition for current state
          return
        end

        new_state = opts[:next_state]
        action = opts[:action]

        if next_instructions_key = opts[:next_instructions_key]
          @next_instructions_key = next_instructions_key
        end

        if new_post = self.send(action)
          @state = @data[:state] = new_state
          @data[:last_post_id] = new_post.id
          store_data

          self.send("init_#{new_state}") if self.class.private_method_defined?("init_#{new_state}")

          if new_state == :end
            end_reply
            cancel_timeout_job(user)
          end
        end
      end
    end

    def notify_timeout(user)
      @data = DiscourseNarrativeBot::Store.get(user.id) || {}

      if post = Post.find_by(id: @data[:last_post_id])
        reply_to(
          raw: I18n.t(i18n_key("timeout.message"), username: user.username, reset_trigger: RESET_TRIGGER),
          topic_id: post.topic.id,
          reply_to_post_number: post.post_number
        )
      end
    end

    private

    def init_tutorial_search
      topic = @post.topic
      post = topic.first_post

      raw = <<~RAW
      #{post.raw}

      #{I18n.t(i18n_key('search.hidden_message'))}
      RAW

      PostRevisor.new(post, topic).revise!(
        self.class.discobot_user,
        { raw: raw },
        { skip_validations: true, force_new_version: true }
      )

      set_state_data(:post_version, post.reload.version)
    end

    def say_hello
      raw = I18n.t(
        i18n_key("hello.message_#{Time.now.to_i % 6 + 1}"),
        username: @user.username,
        title: SiteSetting.title
      )

      raw = <<~RAW
      #{raw}

      #{I18n.t(i18n_key('hello.triggers'))}
      RAW

      opts = {
        title: I18n.t(i18n_key("hello.title"), title: SiteSetting.title),
        raw: raw,
        target_usernames: @user.username,
        archetype: Archetype.private_message
      }

      if @post &&
         @post.archetype == Archetype.private_message &&
         @post.topic.topic_allowed_users.pluck(:user_id).include?(@user.id)

        opts = opts.merge(topic_id: @post.topic_id)
      end

      post = reply_to(opts)
      @data[:topic_id] = post.topic.id
      post
    end

    def react_to_reply
      post_topic_id = @post.topic_id
      return unless valid_topic?(post_topic_id)

      fake_delay

      raw =
        if key = @post.raw.match(/(unicorn|rocket|ninja|monkey)/i)
          I18n.t(i18n_key("start.#{key.to_s.downcase}"))
        else
          I18n.t(i18n_key("start.no_likes_message"))
        end

      raw = <<~RAW
        #{raw}

        #{I18n.t(i18n_key('start.message'))}

        #{I18n.t(i18n_key(@next_instructions_key), profile_page_url: url_helpers(:user_url, username: @user.username))}
      RAW

      reply = reply_to(
        raw: raw,
        topic_id: post_topic_id,
        reply_to_post_number: @post.post_number
      )

      enqueue_timeout_job(@user)
      reply
    end

    def reply_to_bookmark
      return unless valid_topic?(@post.topic_id)
      return unless @post.user_id == -2

      raw = <<~RAW
        #{I18n.t(i18n_key('bookmark.reply'), profile_page_url: url_helpers(:user_url, username: @user.username))}

        #{I18n.t(i18n_key(@next_instructions_key))}
      RAW

      fake_delay

      reply = reply_to(
        raw: raw,
        topic_id: @post.topic_id,
        reply_to_post_number: @post.post_number
      )

      enqueue_timeout_job(@user)
      reply
    end

    def reply_to_onebox
      post_topic_id = @post.topic_id
      return unless valid_topic?(post_topic_id)

      @post.post_analyzer.cook(@post.raw, {})

      if @post.post_analyzer.found_oneboxes?
        raw = <<~RAW
          #{I18n.t(i18n_key('onebox.reply'))}

          #{I18n.t(i18n_key(@next_instructions_key))}
        RAW

        fake_delay

        reply = reply_to(
          raw: raw,
          topic_id: post_topic_id,
          reply_to_post_number: @post.post_number
        )

        enqueue_timeout_job(@user)
        reply
      else
        fake_delay

        reply_to(
          raw: I18n.t(i18n_key('onebox.not_found')),
          topic_id: post_topic_id,
          reply_to_post_number: @post.post_number
        )

        enqueue_timeout_job(@user)
        false
      end
    end

    def track_like
      post_topic_id = @post.topic_id
      return unless valid_topic?(post_topic_id)

      post_liked = PostAction.find_by(
        post_action_type_id: PostActionType.types[:like],
        post_id: @data[:last_post_id],
        user_id: @user.id
      )

      if post_liked
        set_state_data(:liked, true)

        if (post_id = get_state_data(:post_id)) && (post = Post.find_by(id: post_id))
          fake_delay
          like_post(post)

          raw = <<~RAW
            #{I18n.t(i18n_key('images.reply'))}

            #{I18n.t(i18n_key(@next_instructions_key))}
          RAW

          reply = reply_to(
            raw: raw,
            topic_id: post.topic.id,
            reply_to_post_number: post.post_number
          )
          enqueue_timeout_job(@user)
          return reply
        end
      end

      false
    end

    def reply_to_image
      post_topic_id = @post.topic_id
      return unless valid_topic?(post_topic_id)

      @post.post_analyzer.cook(@post.raw, {})
      transition = true

      if @post.post_analyzer.image_count > 0
        set_state_data(:post_id, @post.id)

        if get_state_data(:liked)
          raw = <<~RAW
            #{I18n.t(i18n_key('images.reply'))}

            #{I18n.t(i18n_key(@next_instructions_key))}
          RAW

          like_post(@post)
        else
          raw = I18n.t(
            i18n_key('images.like_not_found'),
            url: Post.find_by(id: @data[:last_post_id]).url
          )

          transition = false
        end
      else
        raw = I18n.t(i18n_key('images.not_found'))
        transition = false
      end

      fake_delay

      reply = reply_to(
        raw: raw,
        topic_id: post_topic_id,
        reply_to_post_number: @post.post_number
      )

      enqueue_timeout_job(@user)
      transition ? reply : false
    end

    def reply_to_formatting
      post_topic_id = @post.topic_id
      return unless valid_topic?(post_topic_id)

      if Nokogiri::HTML.fragment(@post.cooked).css("b", "strong", "em", "i", ".bbcode-i", ".bbcode-b").size > 0
        raw = <<~RAW
          #{I18n.t(i18n_key('formatting.reply'))}

          #{I18n.t(i18n_key(@next_instructions_key))}
        RAW

        fake_delay

        reply = reply_to(
          raw: raw,
          topic_id: post_topic_id,
          reply_to_post_number: @post.post_number
        )

        enqueue_timeout_job(@user)
        reply
      else
        fake_delay

        reply_to(
          raw: I18n.t(i18n_key('formatting.not_found')),
          topic_id: post_topic_id,
          reply_to_post_number: @post.post_number
        )

        enqueue_timeout_job(@user)
        false
      end
    end

    def reply_to_quote
      post_topic_id = @post.topic_id
      return unless valid_topic?(post_topic_id)

      doc = Nokogiri::HTML.fragment(@post.cooked)

      if doc.css(".quote").size > 0
        raw = <<~RAW
          #{I18n.t(i18n_key('quoting.reply'))}

          #{I18n.t(i18n_key(@next_instructions_key))}
        RAW

        fake_delay

        reply = reply_to(
          raw: raw,
          topic_id: post_topic_id,
          reply_to_post_number: @post.post_number
        )

        enqueue_timeout_job(@user)
        reply
      else
        fake_delay

        reply_to(
          raw: I18n.t(i18n_key('quoting.not_found')),
          topic_id: post_topic_id,
          reply_to_post_number: @post.post_number
        )

        enqueue_timeout_job(@user)
        false
      end
    end

    def reply_to_emoji
      post_topic_id = @post.topic_id
      return unless valid_topic?(post_topic_id)

      doc = Nokogiri::HTML.fragment(@post.cooked)

      if doc.css(".emoji").size > 0
        raw = <<~RAW
          #{I18n.t(i18n_key('emoji.reply'))}

          #{I18n.t(i18n_key(@next_instructions_key))}
        RAW

        fake_delay

        reply = reply_to(
          raw: raw,
          topic_id: post_topic_id,
          reply_to_post_number: @post.post_number
        )

        enqueue_timeout_job(@user)
        reply
      else
        fake_delay

        reply_to(
          raw: I18n.t(i18n_key('emoji.not_found')),
          topic_id: post_topic_id,
          reply_to_post_number: @post.post_number
        )

        enqueue_timeout_job(@user)
        false
      end
    end

    def reply_to_mention
      post_topic_id = @post.topic_id
      return unless valid_topic?(post_topic_id)

      if bot_mentioned?
        raw = <<~RAW
          #{I18n.t(i18n_key('mention.reply'))}

          #{I18n.t(i18n_key(@next_instructions_key),
              guidelines_url: url_helpers(:guidelines_url),
              about_url: url_helpers(:about_index_url))}
        RAW

        fake_delay

        reply = reply_to(
          raw: raw,
          topic_id: post_topic_id,
          reply_to_post_number: @post.post_number
        )

        enqueue_timeout_job(@user)
        reply
      else
        fake_delay

        reply_to(
          raw: I18n.t(i18n_key('mention.not_found'), username: @user.username),
          topic_id: post_topic_id,
          reply_to_post_number: @post.post_number
        )

        enqueue_timeout_job(@user)
        false
      end
    end

    def bot_mentioned?
      doc = Nokogiri::HTML.fragment(@post.cooked)

      valid = false

      doc.css(".mention").each do |mention|
        valid = true if mention.text == "@#{self.class.discobot_user.username}"
      end

      valid
    end

    def reply_to_flag
      post_topic_id = @post.topic_id
      return unless valid_topic?(post_topic_id)
      return unless @post.user.id == -2

      topic = welcome_topic
      raw = <<~RAW
        #{I18n.t(i18n_key('flag.reply'))}

        #{I18n.t(i18n_key(@next_instructions_key), topic_id: topic.id, slug: topic.slug)}
      RAW

      fake_delay

      reply = reply_to(
        raw: raw,
        topic_id: post_topic_id,
        reply_to_post_number: @post.post_number
      )

      @post.post_actions.where(user_id: @user.id).destroy_all

      enqueue_timeout_job(@user)
      reply
    end

    def reply_to_link
      post_topic_id = @post.topic_id
      return unless valid_topic?(post_topic_id)

      @post.post_analyzer.cook(@post.raw, {})

      if @post.post_analyzer.link_count > 0
        raw = <<~RAW
          #{I18n.t(i18n_key('link.reply'))}

          #{I18n.t(i18n_key(@next_instructions_key))}
        RAW

        fake_delay

        reply = reply_to(
          raw: raw,
          topic_id: post_topic_id,
          reply_to_post_number: @post.post_number
        )

        enqueue_timeout_job(@user)
        reply
      else
        fake_delay

        topic = welcome_topic
        reply_to(
          raw: I18n.t(i18n_key('link.not_found'), topic_id: topic.id, slug: topic.slug),
          topic_id: post_topic_id,
          reply_to_post_number: @post.post_number
        )

        enqueue_timeout_job(@user)
        false
      end
    end

    def reply_to_search
      post_topic_id = @post.topic_id
      return unless valid_topic?(post_topic_id)

      if @post.raw.match(/#{SEARCH_ANSWER}/)
        fake_delay

        reply = reply_to(
          raw: I18n.t(i18n_key('search.reply'), search_url: url_helpers(:search_url)),
          topic_id: post_topic_id,
          reply_to_post_number: @post.post_number
        )

        first_post = @post.topic.first_post
        first_post.revert_to(get_state_data(:post_version) - 1)
        first_post.save!
        first_post.publish_change_to_clients! :revised

        reply
      else
        fake_delay

        reply_to(
          raw: I18n.t(i18n_key('search.not_found')),
          topic_id: post_topic_id,
          reply_to_post_number: @post.post_number
        )

        enqueue_timeout_job(@user)
        false
      end
    end

    def end_reply
      fake_delay

      reply_to(
        raw: I18n.t(i18n_key('end.message'), username: @user.username, base_url: Discourse.base_url),
        topic_id: @data[:topic_id]
      )
    end

    def valid_topic?(topic_id)
      topic_id == @data[:topic_id]
    end

    def reply_to_bot_post?
      @post&.reply_to_post && @post.reply_to_post.user_id == -2
    end

    def transition
      if @post
        valid_topic = valid_topic?(@post.topic_id)

        if !valid_topic
          raise TransitionError.new if bot_mentioned?
          raise DoNotUnderstandError.new if reply_to_bot_post?
        elsif valid_topic && @state == :end
          raise DoNotUnderstandError.new if reply_to_bot_post?
        end
      end

      TRANSITION_TABLE.fetch([@state, @input])
    rescue KeyError
      raise InvalidTransitionError.new
    end

    def i18n_key(key)
      "discourse_narrative_bot.new_user_narrative.#{key}"
    end

    def reply_to(opts)
      post = PostCreator.create!(self.class.discobot_user, opts)
      reset_rate_limits if post
      post
    end

    def fake_delay
      sleep(rand(2..3)) if Rails.env.production?
    end

    def like_post(post)
      PostAction.act(self.class.discobot_user, post, PostActionType.types[:like])
    end

    def generic_replies
      count = (@data[:do_not_understand_count] ||= 0)

      case count
      when 0
        reply_to(
          raw: I18n.t(i18n_key('do_not_understand.first_response'), reset_trigger: RESET_TRIGGER),
          topic_id: @post.topic_id,
          reply_to_post_number: @post.post_number
        )
      when 1
        reply_to(
          raw: I18n.t(i18n_key('do_not_understand.second_response'), reset_trigger: RESET_TRIGGER),
          topic_id: @post.topic_id,
          reply_to_post_number: @post.post_number
        )
      else
        # Stay out of the user's way
      end

      @data[:do_not_understand_count] += 1
      store_data
    end

    def mention_replies
      post_raw = @post.raw

      raw =
        if match_data = post_raw.match(/roll dice (\d+)d(\d+)/i)
          I18n.t(i18n_key('random_mention.dice'),
            results: Dice.new(match_data[1].to_i, match_data[2].to_i).roll.join(", ")
          )
        elsif match_data = post_raw.match(/show me a quote/i)
          I18n.t(i18n_key('random_mention.quote'), QuoteGenerator.generate)
        else
          I18n.t(i18n_key('random_mention.message'))
        end

      fake_delay

      reply_to(
        raw: raw,
        topic_id: @post.topic_id,
        reply_to_post_number: @post.post_number
      )
    end

    def reset_bot?
      reset = false
      topic_id = @data[:topic_id]

      if @post &&
         bot_mentioned? &&
         valid_topic?(topic_id) &&
         @post.raw.match(/#{RESET_TRIGGER}/)

        reset_data
        set_data({ topic_id: topic_id })
        fake_delay

        reply_to(
          raw: I18n.t(i18n_key('reset.message')),
          topic_id: @post.topic_id,
          reply_to_post_number: @post.post_number
        )

        reset = true
      end

      reset
    end

    def cancel_timeout_job(user)
      Jobs.cancel_scheduled_job(:new_user_narrative_timeout, user_id: user.id)
    end

    def enqueue_timeout_job(user)
      return if Rails.env.test?

      cancel_timeout_job(user)
      Jobs.enqueue_in(TIMEOUT_DURATION, :new_user_narrative_timeout, user_id: user.id)
    end

    def store_data
      set_data(@data)
    end

    def reset_data
      set_data(nil)
    end

    def reset_rate_limits
      if @post
        @post.default_rate_limiter.rollback!
        @post.limit_posts_per_day&.rollback!
      end
    end

    def welcome_topic
      Topic.find_by(slug: 'welcome-to-discourse', archetype: Archetype.default) ||
        Topic.recent(1).first
    end

    def set_data(value)
      DiscourseNarrativeBot::Store.set(@user.id, value)
    end

    def set_state_data(key, value)
      @data[@state] ||= {}
      @data[@state][key] = value
      set_data(@data)
    end

    def get_state_data(key)
      @data[@state] ||= {}
      @data[@state][key]
    end

    def self.discobot_user
      @discobot ||= User.find(-2)
    end

    def url_helpers(url, opts = {})
      Rails.application.routes.url_helpers.send(url, opts.merge(host: Discourse.base_url))
    end
  end
end
