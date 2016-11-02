module Jobs
  class NewUserNarrativeTimeout < Jobs::Base
    def execute(args)
      if user = User.find_by(id: args[:user_id])
        DiscourseNarrativeBot::NewUserNarrative.new.notify_timeout(user)
      end
    end
  end
end
