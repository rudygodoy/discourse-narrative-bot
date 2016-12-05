module Jobs
  class AdvancedUserNarrativeInit < Jobs::Base
    def execute(args)
      if user = User.find_by(id: args[:user_id])
        DiscourseNarrativeBot::AdvancedUserNarrative.new.input(:init, user)
      end
    end
  end
end
