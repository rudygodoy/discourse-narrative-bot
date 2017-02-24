module Jobs
  class BotInput < Jobs::Base

    sidekiq_options queue: 'critical', retry: 1

    def execute(args)
      user = User.find_by(id: args[:user_id])

      return unless user

      post = Post.find_by(id: args[:post_id])

      DiscourseNarrativeBot::TrackSelector.new(args[:input].to_sym, user, post).select
    end
  end
end
