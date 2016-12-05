require 'rails_helper'

RSpec.describe DiscourseNarrativeBot::AdvancedUserNarrative do
  let(:first_post) { Fabricate(:post) }
  let(:topic) { Fabricate(:private_message_topic, first_post: first_post) }
  let(:user) { topic.user }
  let(:post) { Fabricate(:post, topic: topic, user: user) }
  let(:narrative) { described_class.new }
  let(:other_topic) { Fabricate(:topic) }
  let(:other_post) { Fabricate(:post, topic: other_topic) }
  let(:discobot_user) { User.find(-2) }

  describe '#notify_timeout' do
    before do
      narrative.set_data(user,
        state: :tutorial_poll,
        topic_id: topic.id,
        last_post_id: post.id
      )
    end

    it 'should create the right message' do
      expect { narrative.notify_timeout(user) }.to change { Post.count }.by(1)

      expect(Post.last.raw).to eq(I18n.t(
        'discourse_narrative_bot.timeout.message',
        username: user.username,
        reset_trigger: described_class::RESET_TRIGGER,
        discobot_username: discobot_user.username
      ))
    end
  end

  describe '#reset_bot' do
    before do
      narrative.set_data(user, state: :tutorial_images, topic_id: topic.id)
    end

    context 'when trigger is initiated in a PM' do
      let(:user) { Fabricate(:user) }

      let(:topic) do
        topic_allowed_user = Fabricate.build(:topic_allowed_user, user: user)
        bot = Fabricate.build(:topic_allowed_user, user: discobot_user)
        Fabricate(:private_message_topic, topic_allowed_users: [topic_allowed_user, bot])
      end

      let(:post) { Fabricate(:post, topic: topic) }

      it 'should reset the bot' do
        narrative.reset_bot(user, post)

        expected_raw = I18n.t(
          'discourse_narrative_bot.advanced_user_narrative.start_message',
          username: user.username
        )

        expected_raw = <<~RAW
        #{expected_raw}

        #{I18n.t('discourse_narrative_bot.advanced_user_narrative.poll.instructions')}
        RAW

        new_post = Post.last

        expect(narrative.get_data(user)).to eq({
          "topic_id" => topic.id,
          "state" => "tutorial_poll",
          "last_post_id" => new_post.id
        })

        expect(new_post.raw).to eq(expected_raw.chomp)
        expect(new_post.topic.id).to eq(topic.id)
      end
    end

    context 'when trigger is not initiated in a PM' do
      it 'should start the new track in a PM' do
        narrative.reset_bot(user, other_post)

        expected_raw = I18n.t(
          'discourse_narrative_bot.advanced_user_narrative.start_message',
          username: user.username
        )

        expected_raw = <<~RAW
        #{expected_raw}

        #{I18n.t('discourse_narrative_bot.advanced_user_narrative.poll.instructions')}
        RAW

        new_post = Post.last

        expect(narrative.get_data(user)).to eq({
          "topic_id" => new_post.topic.id,
          "state" => "tutorial_poll",
          "last_post_id" => new_post.id
        })

        expect(new_post.raw).to eq(expected_raw.chomp)
        expect(new_post.topic.id).to_not eq(topic.id)
      end
    end
  end

  describe "#input" do
    context 'poll tutorial' do
      before do
        narrative.set_data(user, state: :tutorial_poll, topic_id: topic.id)
      end

      describe 'when post is not in the right topic' do
        it 'should not do anything' do
          other_post
          narrative.expects(:enqueue_timeout_job).with(user).never

          expect { narrative.input(:reply, user, other_post) }.to_not change { Post.count }
          expect(narrative.get_data(user)[:state].to_sym).to eq(:tutorial_poll)
        end
      end

      describe 'when user replies to the topic' do
        it 'should create the right reply' do
          narrative.input(:reply, user, post)
          new_post = Post.last

          expect(new_post.raw).to eq(I18n.t('discourse_narrative_bot.advanced_user_narrative.poll.not_found'))
          expect(narrative.get_data(user)[:state].to_sym).to eq(:tutorial_poll)
        end
      end

      it 'should create the right reply' do
        post.update_attributes!(
          raw: "[poll]\n* 1\n* 2\n[/poll]\n"
        )

        narrative.input(:reply, user, post)
        new_post = Post.offset(1).last

        expected_raw = <<~RAW
          #{I18n.t('discourse_narrative_bot.advanced_user_narrative.poll.reply')}
        RAW

        expect(new_post.raw).to eq(expected_raw.chomp)

        expect(narrative.get_data(user)).to eq({
          "state" => 'end', "topic_id" => new_post.topic_id
        })
      end
    end
  end
end
