module Jobs
  class NewUserNarrativeReply < Jobs::Base

    sidekiq_options queue: 'critical'

    def execute(args)
      user = User.find args[:user_id]
      post = Post.find args[:post_id] rescue nil

      DiscourseNarrativeBot::NewUserNarrative.new.input(args[:input].to_sym, user, post)
    end
  end
end
