require 'rails_helper'

describe DiscourseNarrativeBot::TrackSelector do
  let(:user) { Fabricate(:user) }
  let(:post) { Fabricate(:post, user: user) }
  let(:discobot_user) { described_class.discobot_user }
  let(:bot_post) { Fabricate(:post, topic: post.topic, user: discobot_user) }
  let(:narrative) { DiscourseNarrativeBot::NewUserNarrative.new }

  describe '#select' do
    context 'when a track is in progress' do
      before do
        narrative.set_data(user,
          state: :tutorial_images,
          topic_id: post.topic.id
        )
      end

      context 'when bot is mentioned' do
        it 'should select the right track' do
          post.update_attributes!(raw: '@discobot show me what you can do')
          described_class.new(:reply, user, post).select
          new_post = Post.last

          expect(new_post.raw).to eq(I18n.t(
            "discourse_narrative_bot.new_user_narrative.images.not_found"
          ))
        end
      end

      context 'when bot is replied to' do
        it 'should select the right track' do
          Timecop.freeze(Time.new(2016, 10, 31, 16, 30)) do
            post.update_attributes!(
              raw: 'show me what you can do',
              reply_to_post_number: bot_post.post_number
            )

            described_class.new(:reply, user, post).select
            new_post = Post.last

            expect(new_post.raw).to eq(I18n.t(
              "discourse_narrative_bot.new_user_narrative.images.not_found"
            ))
          end
        end
      end

      context 'when reply contains a reset trigger' do
        it 'should start/reset the track' do
          post.update_attributes!(
            raw: "@discobot #{DiscourseNarrativeBot::NewUserNarrative::RESET_TRIGGER}"
          )

          described_class.new(:reply, user, post).select

          expect(DiscourseNarrativeBot::NewUserNarrative.new.get_data(user)['state'])
            .to eq("waiting_reply")
        end
      end
    end

    context 'random discobot mentions' do
      describe 'when discobot is mentioned' do
        it 'should create the right reply' do
          post.update_attributes!(raw: 'Show me what you can do @discobot')
          described_class.new(:reply, user, post).select
          new_post = Post.last

          expect(new_post.raw).to eq(I18n.t(
            "discourse_narrative_bot.track_selector.random_mention.message",
            discobot_username: described_class.discobot_user.username,
            new_user_track: DiscourseNarrativeBot::NewUserNarrative::RESET_TRIGGER
          ))
        end

        context 'when discobot is mentioned at the end of a track' do
          before do
            narrative.set_data(user, state: :end, topic_id: post.topic.id)
          end

          it 'should create the right reply' do
            post.update_attributes!(raw: 'Show me what you can do @discobot')
            described_class.new(:reply, user, post).select
            new_post = Post.last

            expect(new_post.raw).to eq(I18n.t(
              "discourse_narrative_bot.track_selector.random_mention.message",
              discobot_username: described_class.discobot_user.username,
              new_user_track: DiscourseNarrativeBot::NewUserNarrative::RESET_TRIGGER
            ))
          end
        end

        describe 'when discobot is asked to roll dice' do
          it 'should create the right reply' do
            post.update_attributes!(raw: '@discobot roll 2d1')
            described_class.new(:reply, user, post).select
            new_post = Post.last

            expect(new_post.raw).to eq(
              I18n.t("discourse_narrative_bot.track_selector.random_mention.dice",
              results: '1, 1'
            ))
          end
        end

        describe 'when a quote is requested' do
          it 'should create the right reply' do
            QuoteGenerator.expects(:generate).returns(
              quote: "Be Like Water", author: "Bruce Lee"
            )

            post.update_attributes!(raw: '@discobot show me a quote')
            described_class.new(:reply, user, post).select
            new_post = Post.last

            expect(new_post.raw).to eq(
              I18n.t("discourse_narrative_bot.track_selector.random_mention.quote",
              quote: "Be Like Water", author: "Bruce Lee"
            ))
          end
        end
      end
    end

    context 'pms to bot' do
      let(:other_topic) do
        topic_allowed_user = Fabricate.build(:topic_allowed_user, user: user)
        bot = Fabricate.build(:topic_allowed_user, user: discobot_user)
        Fabricate(:private_message_topic, topic_allowed_users: [topic_allowed_user, bot])
      end

      let(:other_post) { Fabricate(:post, topic: other_topic) }

      describe 'when a new like is made' do
        it 'should not do anything' do
          other_post
          expect { described_class.new(:like, user, other_post).select }.to_not change { Post.count }
        end
      end

      describe 'when a new message is made' do
        it 'should create the right reply' do
          described_class.new(:reply, user, other_post).select

          expect(Post.last.raw).to eq(I18n.t(
            "discourse_narrative_bot.track_selector.random_mention.message",
            discobot_username: discobot_user.username,
            new_user_track: DiscourseNarrativeBot::NewUserNarrative::RESET_TRIGGER
          ))
        end
      end
    end

    context 'generic replies' do
      before do
        narrative.set_data(user, state: :end, topic_id: post.topic.id)
      end

      after do
        $redis.del("#{described_class::GENERIC_REPLIEX_COUNT_PREFIX}#{user.id}")
      end

      it 'should create the right generic do not understand responses' do
        post.update_attributes!(reply_to_post_number: bot_post.post_number)

        described_class.new(:reply, user, post).select
        new_post = Post.last

        expect(new_post.raw).to eq(I18n.t(
          'discourse_narrative_bot.track_selector.do_not_understand.first_response',
          reset_trigger: DiscourseNarrativeBot::NewUserNarrative::RESET_TRIGGER,
          discobot_username: discobot_user.username
        ))

        described_class.new(:reply, user, Fabricate(:post,
          topic: new_post.topic,
          user: user,
          reply_to_post_number: new_post.post_number
        )).select

        new_post = Post.last

        expect(new_post.raw).to eq(I18n.t(
          'discourse_narrative_bot.track_selector.do_not_understand.second_response',
          reset_trigger: DiscourseNarrativeBot::NewUserNarrative::RESET_TRIGGER,
          discobot_username: discobot_user.username
        ))

        new_post = Fabricate(:post,
          topic: new_post.topic,
          user: user,
          reply_to_post_number: new_post.post_number
        )

        expect { described_class.new(:reply, user, new_post).select }.to_not change { Post.count }
      end
    end
  end
end
