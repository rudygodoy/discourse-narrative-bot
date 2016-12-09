module DiscourseNarrativeBot
  module Actions
    extend ActiveSupport::Concern

    included do
      def self.discobot_user
        @discobot ||= User.find(-2)
      end
    end

    private

    def reply_to(post, raw, opts = {})
      if post
        default_opts = {
          raw: raw,
          topic_id: post.topic_id,
          reply_to_post_number: post.post_number
        }

        new_post = PostCreator.create!(self.class.discobot_user, default_opts.merge(opts))
        reset_rate_limits(post) if new_post
        new_post
      else
        PostCreator.create!(self.class.discobot_user, { raw: raw }.merge(opts))
      end
    end

    def reset_rate_limits(post)
      post.default_rate_limiter.rollback!
      post.limit_posts_per_day&.rollback!
    end

    def fake_delay
      sleep(rand(2..3)) if Rails.env.production?
    end

    def bot_mentioned?(post)
      doc = Nokogiri::HTML.fragment(post.cooked)

      valid = false

      doc.css(".mention").each do |mention|
        valid = true if mention.text == "@#{self.class.discobot_user.username}"
      end

      valid
    end

    def reply_to_bot_post?(post)
      post&.reply_to_post && post.reply_to_post.user_id == -2
    end

    def pm_to_bot?(post)
      topic = post.topic

      return false unless topic.archetype == Archetype.private_message

      allowed_users = topic.allowed_users.pluck(:id)

      allowed_users.delete(-2) &&
        allowed_users.length == 1 &&
        topic.allowed_groups.length == 0
    end
  end
end
