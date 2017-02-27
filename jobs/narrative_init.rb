module Jobs
  class NarrativeInit < Jobs::Base
    def execute(args)
      if user = User.find_by(id: args[:user_id])
        args[:klass].constantize.new.input(:init, user)
      end
    end
  end
end
