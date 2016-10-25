module Jobs
  class NarrativeInput < Jobs::Base

    sidekiq_options queue: 'critical'

    def execute(args)
      user = User.find args[:user_id]
      post = Post.find args[:post_id] rescue nil

      narrative = ::DiscourseNarrativeBot::Narrative.new(
        args[:narrative],
        ::DiscourseNarrativeBot::Store.get(args[:narrative], user.id)
      )

      narrative.on_data do | data |
        ::DiscourseNarrativeBot::Store.set(args[:narrative], user.id, data)
      end

      narrative.input args[:input], user, post
    end
  end
end
