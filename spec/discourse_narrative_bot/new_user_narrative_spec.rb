require 'rails_helper'

describe DiscourseNarrativeBot::NewUserNarrative do
  let!(:welcome_topic) { Fabricate(:topic, title: 'Welcome to Discourse') }
  let(:topic) { Fabricate(:private_message_topic) }
  let(:user) { topic.user }
  let(:post) { Fabricate(:post, topic: topic, user: user) }
  let(:narrative) { described_class.new }
  let(:other_topic) { Fabricate(:topic) }
  let(:other_post) { Fabricate(:post, topic: other_topic) }

  describe '#notify_timeout' do
    before do
      DiscourseNarrativeBot::Store.set(user.id,
        state: :tutorial_images,
        topic_id: topic.id,
        last_post_id: post.id
      )
    end

    it 'should create the right message' do
      expect { narrative.notify_timeout(user) }.to change { Post.count }.by(1)

      expect(Post.last.raw).to eq(I18n.t(
        'discourse_narrative_bot.new_user_narrative.timeout.message',
        username: user.username
      ))
    end
  end

  describe '#input' do
    before do
      SiteSetting.title = "This is an awesome site!"
      DiscourseNarrativeBot::Store.set(user.id, state: :begin)
    end

    describe 'when post contains the right reset trigger' do
      before do
        DiscourseNarrativeBot::Store.set(user.id, state: :tutorial_images, topic_id: topic.id)
      end

      it 'should reset the bot' do
        post.update_attributes!(raw: "@discobot something #{described_class::RESET_TRIGGER}")
        narrative.input(:reply, user, post)

        expect(DiscourseNarrativeBot::Store.get(user.id)).to eq({ "topic_id" => topic.id })

        expect(Post.last.raw).to eq(I18n.t(
          'discourse_narrative_bot.new_user_narrative.reset.message'
        ))

        Timecop.freeze(Time.new(2016, 10, 31, 16, 30)) do
          expected_raw = I18n.t('discourse_narrative_bot.new_user_narrative.hello.message_1',
            username: user.username, title: SiteSetting.title
          )

          expected_raw = <<~RAW
          #{expected_raw}

          #{I18n.t('discourse_narrative_bot.new_user_narrative.hello.triggers')}
          RAW

          narrative.input(
            :reply,
            user,
            Fabricate(:post, topic: topic, raw: '@discobot hi there!!')
          )

          new_post = Post.last
          expect(new_post.raw).to eq(expected_raw.chomp)
          expect(new_post.topic.id).to eq(topic.id)
        end
      end
    end

    describe 'when input does not have a valid transition from current state' do
      it 'should raise the right error' do
        expect { narrative.input(:something, user, post) }.to raise_error(
          described_class::InvalidTransitionError,
          "No transition from state 'begin' for input 'something'"
        )
      end
    end

    describe 'when [:begin, :init]' do
      it 'should create the right post' do
        Timecop.freeze(Time.new(2016, 10, 31, 16, 30)) do
          narrative.input(:init, user, nil)
          new_post = Post.last

          expected_raw = I18n.t('discourse_narrative_bot.new_user_narrative.hello.message_1',
            username: user.username, title: SiteSetting.title
          )

          expected_raw = <<~RAW
          #{expected_raw}

          #{I18n.t('discourse_narrative_bot.new_user_narrative.hello.triggers')}
          RAW

          expect(new_post.raw).to eq(expected_raw.chomp)

          expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym)
            .to eq(:waiting_reply)
        end
      end
    end

    describe 'when [:waiting_reply, :reply]' do
      let(:post) { Fabricate(:post, topic_id: topic.id) }
      let(:other_post) { Fabricate(:post) }

      before do
        DiscourseNarrativeBot::Store.set(user.id, state: :waiting_reply, topic_id: topic.id)
      end

      describe 'when post is not from the right topic' do
        it 'should not do anything' do
          post
          other_post

          narrative.expects(:enqueue_timeout_job).with(user).never
          expect { narrative.input(:reply, user, other_post) }.to_not change { Post.count }
          expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:waiting_reply)
        end
      end

      describe 'when post contains the right text' do
        it 'should create the right reply' do
          narrative.expects(:enqueue_timeout_job).with(user)
          post.update_attributes!(raw: 'omg this is a UnicoRn!')

          narrative.input(:reply, user, post)
          new_post = Post.last

          expected_raw = <<~RAW
            #{I18n.t('discourse_narrative_bot.new_user_narrative.start.unicorn')}

            #{I18n.t('discourse_narrative_bot.new_user_narrative.start.message')}

            #{I18n.t('discourse_narrative_bot.new_user_narrative.onebox.instructions')}
          RAW

          expect(new_post.raw).to eq(expected_raw.chomp)

          data = DiscourseNarrativeBot::Store.get(user.id)

          expect(data[:state].to_sym).to eq(:tutorial_onebox)
          expect(data[:last_post_id]).to eq(new_post.id)
        end
      end

      describe 'when post does not contain the right text' do
        it 'should create the right reply' do
          narrative.expects(:enqueue_timeout_job).with(user)
          post.update_attributes!(raw: 'omg this is a horse!')

          narrative.input(:reply, user, post)
          new_post = Post.last

          expected_raw = <<~RAW
            #{I18n.t('discourse_narrative_bot.new_user_narrative.start.no_likes_message')}

            #{I18n.t('discourse_narrative_bot.new_user_narrative.start.message')}

            #{I18n.t('discourse_narrative_bot.new_user_narrative.onebox.instructions')}
          RAW

          expect(new_post.raw).to eq(expected_raw.chomp)

          data = DiscourseNarrativeBot::Store.get(user.id)

          expect(data[:state].to_sym).to eq(:tutorial_onebox)
          expect(data[:last_post_id]).to eq(new_post.id)
        end
      end
    end

    describe 'when [:tutorial_onebox, :reply]' do
      before do
        DiscourseNarrativeBot::Store.set(user.id, state: :tutorial_onebox, topic_id: topic.id)
      end

      describe 'when post is not in the right topic' do
        it 'should not do anything' do
          other_post
          narrative.expects(:enqueue_timeout_job).with(user).never

          expect { narrative.input(:reply, user, other_post) }.to_not change { Post.count }
          expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:tutorial_onebox)
        end
      end

      describe 'when post does not contain onebox' do
        it 'should create the right reply' do
          narrative.expects(:enqueue_timeout_job).with(user)
          narrative.input(:reply, user, post)
          new_post = Post.last

          expect(new_post.raw).to eq(I18n.t('discourse_narrative_bot.new_user_narrative.onebox.not_found'))
          expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:tutorial_onebox)
        end
      end

      it 'should create the right reply' do
        post.update_attributes!(raw: 'https://en.wikipedia.org/wiki/ROT13')

        narrative.expects(:enqueue_timeout_job).with(user)
        narrative.input(:reply, user, post)
        new_post = Post.last

        expected_raw = <<~RAW
          #{I18n.t('discourse_narrative_bot.new_user_narrative.onebox.reply')}

          #{I18n.t('discourse_narrative_bot.new_user_narrative.images.instructions')}
        RAW

        expect(new_post.raw).to eq(expected_raw.chomp)
        expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:tutorial_images)
      end
    end

    describe 'when [:tutorial_images, :reply]' do
      before do
        DiscourseNarrativeBot::Store.set(user.id, state: :tutorial_images, topic_id: topic.id)
      end

      describe 'when post is not in the right topic' do
        it 'should not do anything' do
          other_post
          narrative.expects(:enqueue_timeout_job).with(user).never

          expect { narrative.input(:reply, user, other_post) }.to_not change { Post.count }
          expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:tutorial_images)
        end
      end

      describe 'when post does not contain an image' do
        it 'should create the right reply' do
          narrative.expects(:enqueue_timeout_job).with(user)
          narrative.input(:reply, user, post)

          expect(Post.last.raw).to eq(I18n.t('discourse_narrative_bot.new_user_narrative.images.not_found'))
          expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:tutorial_images)
        end
      end

      it 'should create the right reply' do
        post.update_attributes!(
          raw: "<img src='https://i.ytimg.com/vi/tntOCGkgt98/maxresdefault.jpg'>",
        )

        narrative.expects(:enqueue_timeout_job).with(user)
        narrative.input(:reply, user, post)
        new_post = Post.last

        expected_raw = <<~RAW
          #{I18n.t('discourse_narrative_bot.new_user_narrative.images.reply')}

          #{I18n.t('discourse_narrative_bot.new_user_narrative.formatting.instructions')}
        RAW

        post_action = PostAction.last

        expect(post_action.post_action_type_id).to eq(PostActionType.types[:like])
        expect(post_action.user).to eq(described_class.discobot_user)
        expect(post_action.post).to eq(post)
        expect(new_post.raw).to eq(expected_raw.chomp)
        expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:tutorial_formatting)
      end
    end

    describe 'when [:tutorial_formatting, :reply]' do
      before do
        DiscourseNarrativeBot::Store.set(user.id, state: :tutorial_formatting, topic_id: topic.id)
      end

      describe 'when post is not in the right topic' do
        it 'should not do anything' do
          other_post
          narrative.expects(:enqueue_timeout_job).with(user).never

          expect { narrative.input(:reply, user, other_post) }.to_not change { Post.count }
          expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:tutorial_formatting)
        end
      end

      describe 'when post does not contain any formatting' do
        it 'should create the right reply' do
          narrative.expects(:enqueue_timeout_job).with(user)
          narrative.input(:reply, user, post)

          expect(Post.last.raw).to eq(I18n.t('discourse_narrative_bot.new_user_narrative.formatting.not_found'))
          expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:tutorial_formatting)
        end
      end

      it 'should create the right reply' do
        post.update_attributes!(raw: "**bold** __italic__")

        narrative.expects(:enqueue_timeout_job).with(user)
        narrative.input(:reply, user, post)
        new_post = Post.last

        expected_raw = <<~RAW
          #{I18n.t('discourse_narrative_bot.new_user_narrative.formatting.reply')}

          #{I18n.t('discourse_narrative_bot.new_user_narrative.quoting.instructions')}
        RAW

        expect(new_post.raw).to eq(expected_raw.chomp)
        expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:tutorial_quote)
      end
    end

    describe 'when [:tutorial_quote, :reply]' do
      before do
        DiscourseNarrativeBot::Store.set(user.id, state: :tutorial_quote, topic_id: topic.id)
      end

      describe 'when post is not in the right topic' do
        it 'should not do anything' do
          other_post
          narrative.expects(:enqueue_timeout_job).with(user).never

          expect { narrative.input(:reply, user, other_post) }.to_not change { Post.count }
          expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:tutorial_quote)
        end
      end

      describe 'when post does not contain any quotes' do
        it 'should create the right reply' do
          narrative.expects(:enqueue_timeout_job).with(user)
          narrative.input(:reply, user, post)

          expect(Post.last.raw).to eq(I18n.t('discourse_narrative_bot.new_user_narrative.quoting.not_found'))
          expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:tutorial_quote)
        end
      end

      it 'should create the right reply' do
        post.update_attributes!(
          raw: '[quote="#{post.user}, post:#{post.post_number}, topic:#{topic.id}"]\n:monkey: :fries:\n[/quote]'
        )

        narrative.expects(:enqueue_timeout_job).with(user)
        narrative.input(:reply, user, post)
        new_post = Post.last

        expected_raw = <<~RAW
          #{I18n.t('discourse_narrative_bot.new_user_narrative.quoting.reply')}

          #{I18n.t('discourse_narrative_bot.new_user_narrative.emoji.instructions')}
        RAW

        expect(new_post.raw).to eq(expected_raw.chomp)
        expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:tutorial_emoji)
      end
    end

    describe 'when [:tutorial_emoji, :reply]' do
      before do
        DiscourseNarrativeBot::Store.set(user.id, state: :tutorial_emoji, topic_id: topic.id)
      end

      describe 'when post is not in the right topic' do
        it 'should not do anything' do
          other_post
          narrative.expects(:enqueue_timeout_job).with(user).never

          expect { narrative.input(:reply, user, other_post) }.to_not change { Post.count }
          expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:tutorial_emoji)
        end
      end

      describe 'when post does not contain any emoji' do
        it 'should create the right reply' do
          narrative.expects(:enqueue_timeout_job).with(user)
          narrative.input(:reply, user, post)

          expect(Post.last.raw).to eq(I18n.t('discourse_narrative_bot.new_user_narrative.emoji.not_found'))
          expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:tutorial_emoji)
        end
      end

      it 'should create the right reply' do
        post.update_attributes!(
          raw: ':monkey: :fries:'
        )

        narrative.expects(:enqueue_timeout_job).with(user)
        narrative.input(:reply, user, post)
        new_post = Post.last

        expected_raw = <<~RAW
          #{I18n.t('discourse_narrative_bot.new_user_narrative.emoji.reply')}

          #{I18n.t('discourse_narrative_bot.new_user_narrative.mention.instructions')}
        RAW

        expect(new_post.raw).to eq(expected_raw.chomp)
        expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:tutorial_mention)
      end
    end

    describe 'when [:tutorial_mention, :reply]' do
      before do
        DiscourseNarrativeBot::Store.set(user.id, state: :tutorial_mention, topic_id: topic.id)
      end

      describe 'when post is not in the right topic' do
        it 'should not do anything' do
          other_post
          narrative.expects(:enqueue_timeout_job).with(user).never

          expect { narrative.input(:reply, user, other_post) }.to_not change { Post.count }
          expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:tutorial_mention)
        end
      end

      describe 'when post does not contain any mentions' do
        it 'should create the right reply' do
          narrative.expects(:enqueue_timeout_job).with(user)
          narrative.input(:reply, user, post)

          expect(Post.last.raw).to eq(I18n.t(
            'discourse_narrative_bot.new_user_narrative.mention.not_found',
            username: user.username
          ))

          expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:tutorial_mention)
        end
      end

      it 'should create the right reply' do
        post.update_attributes!(
          raw: '@discobot hello how are you doing today?'
        )

        narrative.expects(:enqueue_timeout_job).with(user)
        narrative.input(:reply, user, post)
        new_post = Post.last

        expected_raw = <<~RAW
          #{I18n.t('discourse_narrative_bot.new_user_narrative.mention.reply')}

          #{I18n.t(
            'discourse_narrative_bot.new_user_narrative.flag.instructions',
            base_url: Discourse.base_url
          )}
        RAW

        expect(new_post.raw).to eq(expected_raw.chomp)
        expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:tutorial_flag)
      end
    end

    describe 'when [:tutorial_flag, :flag]' do
      let(:post) { Fabricate(:post, user: described_class.discobot_user, topic: topic) }
      let(:flag) { Fabricate(:flag, post: post, user: user) }

      before do
        flag
        DiscourseNarrativeBot::Store.set(user.id, state: :tutorial_flag, topic_id: topic.id)
      end

      describe 'when post flagged is not for the right topic' do
        it 'should not do anything' do
          narrative.expects(:enqueue_timeout_job).with(user).never
          flag.update_attributes!(post: other_post)

          expect { narrative.input(:flag, user, flag.post) }.to_not change { Post.count }
          expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:tutorial_flag)
        end
      end

      describe 'when post being flagged does not belong to discobot ' do
        it 'should not do anything' do
          narrative.expects(:enqueue_timeout_job).with(user).never
          flag.update_attributes!(post: other_post)

          expect { narrative.input(:flag, user, flag.post) }.to_not change { Post.count }
          expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:tutorial_flag)
        end
      end

      it 'should create the right reply' do
        narrative.expects(:enqueue_timeout_job).with(user)

        expect  { narrative.input(:flag, user, flag.post) }.to change { PostAction.count }.by(-1)

        new_post = Post.last

        expected_raw = <<~RAW
          #{I18n.t('discourse_narrative_bot.new_user_narrative.flag.reply')}

          #{I18n.t(
            'discourse_narrative_bot.new_user_narrative.link.instructions',
            topic_id: welcome_topic.id, slug: welcome_topic.slug
          )}
        RAW

        expect(new_post.raw).to eq(expected_raw.chomp)
        expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:tutorial_link)
      end
    end

    describe 'when [:tutorial_link, :reply]' do
      before do
        DiscourseNarrativeBot::Store.set(user.id, state: :tutorial_link, topic_id: topic.id)
      end

      describe 'when post is not in the right topic' do
        it 'should not do anything' do
          other_post
          narrative.expects(:enqueue_timeout_job).with(user).never

          expect { narrative.input(:reply, user, other_post) }.to_not change { Post.count }
          expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:tutorial_link)
        end
      end

      describe 'when post does not contain any quotes' do
        it 'should create the right reply' do
          narrative.expects(:enqueue_timeout_job).with(user)
          narrative.input(:reply, user, post)

          expect(Post.last.raw).to eq(I18n.t(
            'discourse_narrative_bot.new_user_narrative.link.not_found',
            topic_id: welcome_topic.id, slug: welcome_topic.slug
          ))

          expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:tutorial_link)
        end
      end

      it 'should create the right reply' do
        pending "somehow it isn't oneboxed in tests"

        post.update_attributes!(
          raw: 'https://try.discourse.org/t/something-to-say/485'
        )

        narrative.expects(:enqueue_timeout_job).with(user)
        narrative.input(:reply, user, post)
        new_post = Post.last

        expected_raw = <<~RAW
          #{I18n.t('discourse_narrative_bot.new_user_narrative.link.reply')}

          #{I18n.t('discourse_narrative_bot.new_user_narrative.search.instructions')}
        RAW

        expect(new_post.raw).to eq(expected_raw.chomp)
        expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:tutorial_search)
      end
    end

    describe 'when [:tutorial_search, :reply]' do
      before do
        DiscourseNarrativeBot::Store.set(user.id, state: :tutorial_search, topic_id: topic.id)
      end

      describe 'when post is not in the right topic' do
        it 'should not do anything' do
          other_post
          narrative.expects(:enqueue_timeout_job).with(user).never

          expect { narrative.input(:reply, user, other_post) }.to_not change { Post.count }
          expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:tutorial_search)
        end
      end

      describe 'when post does not contain the right answer' do
        it 'should create the right reply' do
          narrative.expects(:enqueue_timeout_job).with(user)
          narrative.input(:reply, user, post)

          expect(Post.last.raw).to eq(I18n.t(
            'discourse_narrative_bot.new_user_narrative.search.not_found'
          ))

          expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:tutorial_search)
        end
      end

      describe 'when post contain the right answer' do
        it 'should create the right reply' do
          post.update_attributes!(
            raw: "#{described_class::SEARCH_ANSWER} this is a rabbit"
          )

          narrative.expects(:enqueue_timeout_job).with(user)
          post

          expect { narrative.input(:reply, user, post) }.to change { Post.count }.by(2)
          new_post = Post.offset(1).last

          expect(new_post.raw).to eq(I18n.t(
            'discourse_narrative_bot.new_user_narrative.search.reply',
            base_url: Discourse.base_url
          ).chomp)

          expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:end)
        end
      end
    end

    describe ':end state' do
      before do
        DiscourseNarrativeBot::Store.set(user.id, state: :end, topic_id: topic.id)
      end

      it 'should raise the right error when reply is not in the right topic' do
        expect { narrative.input(:reply, user, other_post) }.to raise_error(
          described_class::InvalidTransitionError
        )
      end

      it 'should create the right generic do not understand responses' do
        discobot_post = Fabricate(:post,
          topic: topic,
          user: described_class.discobot_user
        )

        post = Fabricate(:post,
          topic: topic,
          user: user,
          reply_to_post_number: discobot_post.post_number
        )

        narrative.input(:reply, user, post)

        expect(Post.last.raw).to eq(I18n.t(
          'discourse_narrative_bot.new_user_narrative.do_not_understand.first_response'
        ))

        expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:end)

        narrative.input(:reply, user, Fabricate(:post,
          topic: topic,
          user: user,
          reply_to_post_number: Post.last.post_number
        ))

        expect(Post.last.raw).to eq(I18n.t(
          'discourse_narrative_bot.new_user_narrative.do_not_understand.second_response'
        ))

        expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:end)

        new_post = Fabricate(:post,
          topic: topic,
          user: user,
          reply_to_post_number: Post.last.post_number
        )

        expect { narrative.input(:reply, user, new_post) }.to_not change { Post.count }

        expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:end)
      end
    end

    describe 'random discobot mentions' do
      let(:other_topic) { Fabricate(:topic) }
      let(:other_post) { Fabricate(:post, topic: other_topic) }

      before do
        DiscourseNarrativeBot::Store.set(user.id, state: :tutorial_link, topic_id: topic.id)
      end

      describe 'when discobot is mentioned' do
        it 'should create the right reply' do
          other_post.update_attributes!(raw: 'Show me what you can do @discobot')
          narrative.input(:reply, user, other_post)
          new_post = Post.last

          expect(new_post.raw).to eq(
            I18n.t("discourse_narrative_bot.new_user_narrative.random_mention.message")
          )
        end

        describe 'when discobot is asked to roll dice' do
          it 'should create the right reply' do
            other_post.update_attributes!(raw: '@discobot roll dice 2d1')
            narrative.input(:reply, user, other_post)
            new_post = Post.last

            expect(new_post.raw).to eq(
              I18n.t("discourse_narrative_bot.new_user_narrative.random_mention.dice",
              results: '1, 1'
            ))
          end
        end

        describe 'when a quote is requested' do
          it 'should create the right reply' do
            QuoteGenerator.expects(:generate).returns(
              quote: "Be Like Water", author: "Bruce Lee"
            )

            other_post.update_attributes!(raw: '@discobot show me a quote')
            narrative.input(:reply, user, other_post)
            new_post = Post.last

            expect(new_post.raw).to eq(
              I18n.t("discourse_narrative_bot.new_user_narrative.random_mention.quote",
              quote: "Be Like Water", author: "Bruce Lee"
            ))
          end
        end
      end
    end
  end
end
