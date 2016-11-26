module Jobs
  class NewUserNarrativeInit < Jobs::Base
    def execute(args)
      if user = User.find_by(id: args[:user_id])
        DiscourseNarrativeBot::NewUserNarrative.new.input(:init, user)
      end
    end
  end
end
