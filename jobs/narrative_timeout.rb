module Jobs
  class NarrativeTimeout < Jobs::Base
    def execute(args)
      if user = User.find_by(id: args[:user_id])
        args[:klass].constantize.new.notify_timeout(user)
      end
    end
  end
end
