module Jobs
  class NewUserNarrativeInput < Jobs::Base

    sidekiq_options queue: 'critical', retry: false

    def execute(args)
      user = User.find_by(id: args[:user_id])

      return unless user

      post = Post.find_by(id: args[:post_id])

      DiscourseNarrativeBot::NewUserNarrative.new.input(args[:input].to_sym, user, post)
    end
  end
end
