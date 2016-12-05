module Jobs
  class AdvancedUserNarrativeTimeout < Jobs::Base
    def execute(args)
      if user = User.find_by(id: args[:user_id])
        DiscourseNarrativeBot::AdvancedUserNarrative.new.notify_timeout(user)
      end
    end
  end
end
