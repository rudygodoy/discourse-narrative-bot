module DiscourseNarrativeBot
  class Base
    include Actions

    class InvalidTransitionError < StandardError; end

    def input(input, user, post: nil, topic_id: nil)
      new_post = nil

      synchronize(user) do
        @user = user
        @data = get_data(user) || {}
        @state = (@data[:state] && @data[:state].to_sym) || :begin
        @input = input
        @post = post
        @topic_id = topic_id
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
          old_data = @data.dup

          if new_post = self.send(action)
            old_state = old_data[:state]
            @state = @data[:state] = new_state
            @data[:last_post_id] = new_post.id
            set_data(@user, @data)

            if self.class.private_method_defined?("init_#{new_state}") &&
              old_state.to_s != new_state.to_s

              self.send("init_#{new_state}")
            end

            if new_state == :end
              end_reply
              cancel_timeout_job(user)

              completed = Set.new(get_data(@user)[:completed])
              completed << self.class.to_s

              set_data(@user,
                topic_id: new_post.topic_id,
                state: :end,
                track: self.class.to_s,
                completed: completed
              )
            end
          end
        rescue => e
          @data = old_data
          set_data(@user, @data)
          raise e
        end
      end

      new_post
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

    def set_state_data(key, value)
      @data[@state] ||= {}
      @data[@state][key] = value
      set_data(@user, @data)
    end

    def get_state_data(key)
      @data[@state] ||= {}
      @data[@state][key]
    end

    def reset_data(user, additional_data = {})
      old_data = get_data(user)
      new_data = additional_data
      new_data[:completed] = old_data[:completed] if old_data && old_data[:completed]
      set_data(user, new_data)
      new_data
    end

    def not_implemented
      raise 'Not implemented.'
    end
  end
end
