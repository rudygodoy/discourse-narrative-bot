module DiscourseNarrativeBot
  class AdvancedUserNarrative < Base
    TRANSITION_TABLE = {
      [:begin, :init] => {
        next_state: :tutorial_poll,
        next_instructions_key: 'poll.instructions',
        action: :start_advanced_track
      },

      [:tutorial_poll, :reply] => {
        next_state: :end,
        action: :reply_to_poll
      }
    }

    RESET_TRIGGER = 'advanced user track'.freeze
    TIMEOUT_DURATION = 900 # 15 mins

    def reset_bot(user, post)
      reset_data(user)
      set_data(user, topic_id: post.topic_id) if pm_to_bot?(post)
      Jobs.enqueue_in(2.seconds, :advanced_user_narrative_init, user_id: user.id)
    end

    def notify_timeout(user)
      @data = get_data(user) || {}

      if post = Post.find_by(id: @data[:last_post_id])
        reply_to(post, I18n.t("discourse_narrative_bot.timeout.message",
          username: user.username,
          reset_trigger: RESET_TRIGGER,
          discobot_username: self.class.discobot_user.username
        ))
      end
    end

    private

    def start_advanced_track
      raw = I18n.t(i18n_key("start_message"), username: @user.username)

      raw = <<~RAW
      #{raw}

      #{I18n.t(i18n_key(@next_instructions_key))}
      RAW

      opts = {
        title: I18n.t(i18n_key("title")),
        target_usernames: @user.username,
        archetype: Archetype.private_message
      }

      if @post &&
         @post.archetype == Archetype.private_message &&
         @post.topic.topic_allowed_users.pluck(:user_id).include?(@user.id)

        opts = opts.merge(topic_id: @post.topic_id)
      end

      if @data[:topic_id]
        opts = opts.merge(topic_id: @data[:topic_id])
      end

      post = reply_to(@post, raw, opts)
      @data[:topic_id] = post.topic.id
      @data[:track] = self.class.to_s
      post
    end

    def reply_to_poll
      topic_id = @post.topic_id
      return unless valid_topic?(topic_id)

      fake_delay

      if Nokogiri::HTML.fragment(@post.cooked).css(".poll").size > 0
        reply_to(@post, I18n.t(i18n_key('poll.reply')))
      else
        reply_to(@post, I18n.t(i18n_key('poll.not_found')))
        enqueue_timeout_job(@user)
        false
      end
    end

    def end_reply
      fake_delay
      reply_to(@post, I18n.t(i18n_key('end.message')))
    end

    def transition
      TRANSITION_TABLE.fetch([@state, @input])
    rescue KeyError
      raise InvalidTransitionError.new
    end

    def synchronize(user)
      if Rails.env.test?
        yield
      else
        DistributedMutex.synchronize("advanced_user_narrative_#{user.id}") { yield }
      end
    end

    def i18n_key(key)
      "discourse_narrative_bot.advanced_user_narrative.#{key}"
    end

    def cancel_timeout_job(user)
      Jobs.cancel_scheduled_job(:advanced_user_narrative_timeout, user_id: user.id)
    end

    def enqueue_timeout_job(user)
      return if Rails.env.test?

      cancel_timeout_job(user)
      Jobs.enqueue_in(TIMEOUT_DURATION, :advanced_user_narrative_timeout, user_id: user.id)
    end

    def valid_topic?(topic_id)
      topic_id == @data[:topic_id]
    end
  end
end
