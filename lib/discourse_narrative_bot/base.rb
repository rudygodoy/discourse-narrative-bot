module DiscourseNarrativeBot
  class Base
    include Actions

    class InvalidTransitionError < StandardError; end

    def input(input, user, post = nil)
      synchronize(user) do
        @user = user
        @data = get_data(user) || {}
        @state = (@data[:state] && @data[:state].to_sym) || :begin
        @input = input
        @post = post
        opts = {}

        begin
          opts = transition
        rescue InvalidTransitionError
          # For given input, no transition for current state
          return
        end

        new_state = opts[:next_state]
        action = opts[:action]

        if next_instructions_key = opts[:next_instructions_key]
          @next_instructions_key = next_instructions_key
        end

        begin
          if new_post = self.send(action)
            old_data = @data.dup
            @state = @data[:state] = new_state
            @data[:last_post_id] = new_post.id
            set_data(@user, @data)

            self.send("init_#{new_state}") if self.class.private_method_defined?("init_#{new_state}")

            if new_state == :end
              end_reply
              cancel_timeout_job(user)
              set_data(@user, topic_id: new_post.topic_id, state: :end)
            end
          end
        rescue => e
          @data = old_data
          set_data(@user, @data)
          raise e
        end
      end
    end

    def reset_bot
      not_implemented
    end

    def set_data(user, value)
      DiscourseNarrativeBot::Store.set(user.id, value)
    end

    def get_data(user)
      DiscourseNarrativeBot::Store.get(user.id)
    end

    private

    def reset_data(user)
      set_data(user, nil)
    end

    def not_implemented
      raise 'Not implemented.'
    end
  end
end
