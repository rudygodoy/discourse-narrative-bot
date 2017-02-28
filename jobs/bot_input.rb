module Jobs
  class BotInput < Jobs::Base

    sidekiq_options queue: 'critical', retry: 1

    def execute(args)
      return unless user = User.find_by(id: args[:user_id])

      DiscourseNarrativeBot::TrackSelector.new(args[:input].to_sym, user,
        post_id: args[:post_id],
        topic_id: args[:topic_id]
      ).select
    end
  end
end
