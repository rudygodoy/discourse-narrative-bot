module DiscourseNarrativeBot
  class Narrative
    TRANSITION_TABLE = {
      [:begin, :init] => {
        next_state: :waiting_quote,
        after_action: :say_hello
      },

      [:begin, :reply] => {
        next_state: :waiting_quote,
        after_action: :say_hello
      },

      [:waiting_quote, :reply] => {
        next_state: :tutorial_topic,
        after_action: :quote_user_reply
      },

      [:tutorial_topic, :reply] => {
        next_state: :tutorial_onebox,
        next_instructions_key: 'onebox.instructions',
        after_action: :reply_to_topic
      },

      [:tutorial_onebox, :reply] => {
        next_state: :tutorial_images,
        next_instructions_key: 'images.instructions',
        after_action: :reply_to_onebox
      },

      [:tutorial_images, :reply] => {
        next_state: :tutorial_formatting,
        next_instructions_key: 'formatting.instructions',
        after_action: :reply_to_image
      },

      [:tutorial_formatting, :reply] => {
        next_state: :tutorial_quote,
        next_instructions_key: 'quoting.instructions',
        after_action: :reply_to_formatting
      },

      [:tutorial_quote, :reply] => {
        next_state: :tutorial_emoji,
        next_instructions_key: 'emoji.instructions',
        after_action: :reply_to_quote
      },

      [:tutorial_emoji, :reply] => {
        next_state: :tutorial_mention,
        next_instructions_key: 'mention.instructions',
        after_action: :reply_to_emoji
      },

      [:tutorial_mention, :reply] => {
        next_state: :tutorial_link,
        next_instructions_key: 'link.instructions',
        after_action: :reply_to_mention
      },

      [:tutorial_link, :reply] => {
        next_state: :tutorial_pm,
        next_instructions_key: 'pm.instructions',
        after_action: :reply_to_link
      },

      [:tutorial_pm, :reply] => {
        next_state: :end,
        after_action: :reply_to_pm
      }
    }

    class TransitionError < StandardError; end
    class DoNotUnderstandError < StandardError; end

    def input(input, user, post)
      @data = DiscourseNarrativeBot::Store.get(user.id) || {}
      @state = (@data[:state] && @data[:state].to_sym) || :begin
      @input = input
      @user = user
      @post = post
      opts = {}

      begin
        opts = transition
      rescue DoNotUnderstandError
        generic_replies
        store_data
        return
      end

      new_state = opts[:next_state]
      action = opts[:after_action]

      if next_instructions_key = opts[:next_instructions_key]
        @next_instructions_key = next_instructions_key
      end

      if self.send(action)
        @data[:state] = new_state
        store_data
        end_reply if new_state == :end
      end
    end

    private

    def say_hello
      raw = I18n.t(i18n_key('hello'), username: @user.username, title: SiteSetting.title)

      if @input == :init
        reply_to(raw: raw, topic_id: SiteSetting.discobot_welcome_topic_id)
      else
        return unless bot_mentioned?

        fake_delay
        like_post

        reply_to(
          raw: raw,
          topic_id: @post.topic.id,
          reply_to_post_number: @post.post_number
        )
      end
    end

    def quote_user_reply
      post_topic_id = @post.topic.id
      return unless post_topic_id == SiteSetting.discobot_welcome_topic_id

      fake_delay
      like_post

      reply_to(
        raw: I18n.t(i18n_key('quote_user_reply'),
          username: @post.user.username,
          post_id: @post.id,
          topic_id: post_topic_id,
          post_raw: @post.raw
        ),
        topic_id: post_topic_id,
        reply_to_post_number: @post.post_number
      )
    end

    def reply_to_topic
      return unless @post.topic.category_id == SiteSetting.staff_category_id
      return unless @post.is_first_post?

      post_topic_id = @post.topic.id
      @data[:topic_id] = post_topic_id

      unless key = @post.raw.match(/(unicorn|bacon|ninja|monkey)/i)
        return
      end

      raw = <<~RAW
        #{I18n.t(i18n_key(Regexp.last_match.to_s.downcase))}

        #{I18n.t(i18n_key(@next_instructions_key))}
      RAW

      fake_delay
      like_post

      reply_to(
        raw: raw,
        topic_id: post_topic_id,
        reply_to_post_number: @post.post_number
      )
    end

    def reply_to_onebox
      post_topic_id = @post.topic.id
      return unless valid_topic?(post_topic_id)

      @post.post_analyzer.cook(@post.raw, {})

      if @post.post_analyzer.found_oneboxes?
        raw = <<~RAW
          #{I18n.t(i18n_key('onebox.reply'))}

          #{I18n.t(i18n_key(@next_instructions_key))}
        RAW

        fake_delay
        like_post

        reply_to(
          raw: raw,
          topic_id: post_topic_id,
          reply_to_post_number: @post.post_number
        )
      else
        fake_delay

        reply_to(
          raw: I18n.t(i18n_key('onebox.not_found')),
          topic_id: post_topic_id,
          reply_to_post_number: @post.post_number
        )

        false
      end
    end

    def reply_to_image
      post_topic_id = @post.topic.id
      return unless valid_topic?(post_topic_id)

      @post.post_analyzer.cook(@post.raw, {})

      if @post.post_analyzer.image_count > 0
        raw = <<~RAW
          #{I18n.t(i18n_key('images.reply'))}

          #{I18n.t(i18n_key(@next_instructions_key))}
        RAW

        fake_delay
        like_post

        reply_to(
          raw: raw,
          topic_id: post_topic_id,
          reply_to_post_number: @post.post_number
        )
      else
        fake_delay

        reply_to(
          raw: I18n.t(i18n_key('images.not_found')),
          topic_id: post_topic_id,
          reply_to_post_number: @post.post_number
        )

        false
      end
    end

    def reply_to_formatting
      post_topic_id = @post.topic.id
      return unless valid_topic?(post_topic_id)

      if Nokogiri::HTML.fragment(@post.cooked).css("b", "strong", "em", "i").size > 0
        raw = <<~RAW
          #{I18n.t(i18n_key('formatting.reply'))}

          #{I18n.t(i18n_key(@next_instructions_key))}
        RAW

        fake_delay
        like_post

        reply_to(
          raw: raw,
          topic_id: post_topic_id,
          reply_to_post_number: @post.post_number
        )
      else
        fake_delay

        reply_to(
          raw: I18n.t(i18n_key('formatting.not_found')),
          topic_id: post_topic_id,
          reply_to_post_number: @post.post_number
        )

        false
      end
    end

    def reply_to_quote
      post_topic_id = @post.topic.id
      return unless valid_topic?(post_topic_id)

      doc = Nokogiri::HTML.fragment(@post.cooked)

      if doc.css(".quote").size > 0
        raw = <<~RAW
          #{I18n.t(i18n_key('quoting.reply'))}

          #{I18n.t(i18n_key(@next_instructions_key))}
        RAW

        fake_delay
        like_post

        reply_to(
          raw: raw,
          topic_id: post_topic_id,
          reply_to_post_number: @post.post_number
        )
      else
        fake_delay

        reply_to(
          raw: I18n.t(i18n_key('quoting.not_found')),
          topic_id: post_topic_id,
          reply_to_post_number: @post.post_number
        )

        false
      end
    end

    def reply_to_emoji
      post_topic_id = @post.topic.id
      return unless valid_topic?(post_topic_id)

      doc = Nokogiri::HTML.fragment(@post.cooked)

      if doc.css(".emoji").size > 0
        raw = <<~RAW
          #{I18n.t(i18n_key('emoji.reply'))}

          #{I18n.t(i18n_key(@next_instructions_key))}
        RAW

        fake_delay
        like_post

        reply_to(
          raw: raw,
          topic_id: post_topic_id,
          reply_to_post_number: @post.post_number
        )
      else
        fake_delay

        reply_to(
          raw: I18n.t(i18n_key('emoji.not_found')),
          topic_id: post_topic_id,
          reply_to_post_number: @post.post_number
        )

        false
      end
    end

    def reply_to_mention
      post_topic_id = @post.topic.id
      return unless valid_topic?(post_topic_id)

      if bot_mentioned?
        raw = <<~RAW
          #{I18n.t(i18n_key('mention.reply'))}

          #{I18n.t(i18n_key(@next_instructions_key), topic_id: SiteSetting.discobot_welcome_topic_id)}
        RAW

        fake_delay
        like_post

        reply_to(
          raw: raw,
          topic_id: post_topic_id,
          reply_to_post_number: @post.post_number
        )
      else
        fake_delay

        reply_to(
          raw: I18n.t(i18n_key('mention.not_found'), username: @user.username),
          topic_id: post_topic_id,
          reply_to_post_number: @post.post_number
        )

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

    def reply_to_link
      post_topic_id = @post.topic.id
      return unless valid_topic?(post_topic_id)

      @post.post_analyzer.cook(@post.raw, {})

      if @post.post_analyzer.link_count > 0
        raw = <<~RAW
          #{I18n.t(i18n_key('link.reply'))}

          #{I18n.t(i18n_key(@next_instructions_key))}
        RAW

        fake_delay
        like_post

        reply_to(
          raw: raw,
          topic_id: post_topic_id,
          reply_to_post_number: @post.post_number
        )
      else
        fake_delay

        reply_to(
          raw: I18n.t(i18n_key('link.not_found'), topic_id: SiteSetting.discobot_welcome_topic_id),
          topic_id: post_topic_id,
          reply_to_post_number: @post.post_number
        )

        false
      end
    end

    def reply_to_pm
      if @post.archetype == Archetype.private_message &&
        @post.topic.allowed_users.any? { |p| p.id == self.class.discobot_user.id }

        fake_delay
        like_post

        reply_to(
          raw: I18n.t(i18n_key('pm.message')),
          topic_id: @post.topic.id,
          reply_to_post_number: @post.post_number
        )
      end
    end

    def end_reply
      fake_delay

      reply_to(
        raw: I18n.t(i18n_key('end.message'), username: @user.username),
        topic_id: @data[:topic_id]
      )
    end

    def valid_topic?(topic_id)
      topic_id == @data[:topic_id]
    end

    def transition
      if @state == :end && @post.topic.id == @data[:topic_id]
        raise DoNotUnderstandError.new
      end

      TRANSITION_TABLE.fetch([@state, @input])
    rescue KeyError
      raise TransitionError.new("No transition from state '#{@state}' for input '#{@input}'")
    end

    def i18n_key(key)
      "discourse_narrative_bot.narratives.#{key}"
    end

    def reply_to(opts)
      PostCreator.create!(self.class.discobot_user, opts)
    end

    def fake_delay
      sleep(rand(2..3)) if Rails.env.production?
    end

    def like_post
      PostAction.act(self.class.discobot_user, @post, PostActionType.types[:like])
    end

    def generic_replies
      count = (@data[:do_not_understand_count] ||= 0)

      case count
      when 0
        reply_to(
          raw: I18n.t(i18n_key('do_not_understand.first_response')),
          topic_id: @post.topic.id,
          reply_to_post_number: @post.post_number
        )
      when 1
        reply_to(
          raw: I18n.t(i18n_key('do_not_understand.second_response')),
          topic_id: @post.topic.id,
          reply_to_post_number: @post.post_number
        )
      else
        # Stay out of the user's way
      end

      @data[:do_not_understand_count] += 1
    end

    def store_data
      DiscourseNarrativeBot::Store.set(@user.id, @data)
    end

    def self.discobot_user
      @discobot ||= User.find(-2)
    end
  end
end
