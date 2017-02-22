require 'rails_helper'

describe DiscourseNarrativeBot::NewUserNarrative do
  let!(:welcome_topic) { Fabricate(:topic, title: 'Welcome to Discourse') }
  let(:first_post) { Fabricate(:post) }
  let(:topic) { Fabricate(:private_message_topic, first_post: first_post) }
  let(:user) { topic.user }
  let(:post) { Fabricate(:post, topic: topic, user: user) }
  let(:narrative) { described_class.new }
  let(:other_topic) { Fabricate(:topic) }
  let(:other_post) { Fabricate(:post, topic: other_topic) }
  let(:discobot_user) { User.find(-2) }
  let(:profile_page_url) { "#{Discourse.base_url}/users/#{user.username}" }

  describe '#notify_timeout' do
    before do
      narrative.set_data(user,
        state: :tutorial_images,
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
        Timecop.freeze(Time.new(2016, 10, 31, 16, 30)) do
          narrative.reset_bot(user, post)

          expected_raw = I18n.t('discourse_narrative_bot.new_user_narrative.hello.message_1',
            username: user.username, title: SiteSetting.title
          )

          expected_raw = <<~RAW
          #{expected_raw}

          #{I18n.t('discourse_narrative_bot.new_user_narrative.bookmark.instructions', profile_page_url: profile_page_url)}
          RAW

          new_post = Post.last

          expect(narrative.get_data(user)).to eq({
            "topic_id" => topic.id,
            "state" => "tutorial_bookmark",
            "last_post_id" => new_post.id,
            "track" => described_class.to_s
          })

          expect(new_post.raw).to eq(expected_raw.chomp)
          expect(new_post.topic.id).to eq(topic.id)
        end
      end
    end

    context 'when trigger is not initiated in a PM' do
      it 'should start the new track in a PM' do
        Timecop.freeze(Time.new(2016, 10, 31, 16, 30)) do
          narrative.reset_bot(user, other_post)

          expected_raw = I18n.t('discourse_narrative_bot.new_user_narrative.hello.message_1',
            username: user.username, title: SiteSetting.title
          )

          expected_raw = <<~RAW
          #{expected_raw}

          #{I18n.t('discourse_narrative_bot.new_user_narrative.bookmark.instructions', profile_page_url: profile_page_url)}
          RAW

          new_post = Post.last

          expect(narrative.get_data(user)).to eq({
            "topic_id" => new_post.topic.id,
            "state" => "tutorial_bookmark",
            "last_post_id" => new_post.id,
            "track" => described_class.to_s
          })

          expect(new_post.raw).to eq(expected_raw.chomp)
          expect(new_post.topic.id).to_not eq(topic.id)
        end
      end
    end
  end

  describe '#input' do
    before do
      SiteSetting.title = "This is an awesome site!"
      narrative.set_data(user, state: :begin)
    end

    describe 'when an error occurs' do
      before do
        narrative.set_data(user, state: :tutorial_flag, topic_id: topic.id)
      end

      it 'should revert to the previous state' do
        narrative.expects(:send).with('init_tutorial_search').raises(StandardError.new('some error'))
        narrative.expects(:send).with(:reply_to_flag).returns(post)

        expect { narrative.input(:flag, user, post) }.to raise_error(StandardError, 'some error')
        expect(narrative.get_data(user)[:state].to_sym).to eq(:tutorial_flag)
      end
    end

    describe 'when input does not have a valid transition from current state' do
      before do
        narrative.set_data(user, state: :begin)
      end

      it 'should raise the right error' do
        expect(narrative.input(:something, user, post)).to eq(nil)
        expect(narrative.get_data(user)[:state].to_sym).to eq(:begin)
      end
    end

    describe 'when [:begin, :init]' do
      it 'should create the right post' do
        Timecop.freeze(Time.new(2016, 10, 31, 16, 30)) do
          narrative.expects(:enqueue_timeout_job).never

          narrative.input(:init, user, nil)
          new_post = Post.last

          expected_raw = I18n.t('discourse_narrative_bot.new_user_narrative.hello.message_1',
            username: user.username, title: SiteSetting.title
          )

          expected_raw = <<~RAW
          #{expected_raw}

          #{I18n.t('discourse_narrative_bot.new_user_narrative.bookmark.instructions', profile_page_url: profile_page_url)}
          RAW

          expect(new_post.raw).to eq(expected_raw.chomp)

          expect(narrative.get_data(user)[:state].to_sym)
            .to eq(:tutorial_bookmark)
        end
      end
    end

    describe "bookmark tutorial" do
      before do
        narrative.set_data(user, state: :tutorial_bookmark, topic_id: topic.id)
      end

      describe 'when post is not in the right topic' do
        it 'should not do anything' do
          other_post.update!(user_id: -2)
          narrative.expects(:enqueue_timeout_job).with(user).never

          expect { narrative.input(:bookmark, user, other_post) }.to_not change { Post.count }
          expect(narrative.get_data(user)[:state].to_sym).to eq(:tutorial_bookmark)
        end
      end

      describe "when bookmark is not on bot's post" do
        it 'should not do anything' do
          narrative.expects(:enqueue_timeout_job).with(user).never
          post

          expect { narrative.input(:bookmark, user, post) }.to_not change { Post.count }
          expect(narrative.get_data(user)[:state].to_sym).to eq(:tutorial_bookmark)
        end
      end

      describe 'when user replies to the topic' do
        it 'should create the right reply' do
          narrative.input(:reply, user, post)
          new_post = Post.last

          expect(new_post.raw).to eq(I18n.t('discourse_narrative_bot.new_user_narrative.bookmark.not_found'))
          expect(narrative.get_data(user)[:state].to_sym).to eq(:tutorial_bookmark)
        end
      end

      it 'should create the right reply' do
        post.update!(user: described_class.discobot_user)
        narrative.expects(:enqueue_timeout_job).with(user)

        narrative.input(:bookmark, user, post)
        new_post = Post.last
        profile_page_url = "#{Discourse.base_url}/users/#{user.username}"

        expected_raw = <<~RAW
          #{I18n.t('discourse_narrative_bot.new_user_narrative.bookmark.reply', profile_page_url: profile_page_url)}

          #{I18n.t('discourse_narrative_bot.new_user_narrative.onebox.instructions')}
        RAW

        expect(new_post.raw).to eq(expected_raw.chomp)
        expect(narrative.get_data(user)[:state].to_sym).to eq(:tutorial_onebox)
      end
    end

    describe 'onebox tutorial' do
      before do
        narrative.set_data(user, state: :tutorial_onebox, topic_id: topic.id)
      end

      describe 'when post is not in the right topic' do
        it 'should not do anything' do
          other_post
          narrative.expects(:enqueue_timeout_job).with(user).never

          expect { narrative.input(:reply, user, other_post) }.to_not change { Post.count }
          expect(narrative.get_data(user)[:state].to_sym).to eq(:tutorial_onebox)
        end
      end

      describe 'when post does not contain onebox' do
        it 'should create the right reply' do
          narrative.expects(:enqueue_timeout_job).with(user)
          narrative.input(:reply, user, post)
          new_post = Post.last

          expect(new_post.raw).to eq(I18n.t('discourse_narrative_bot.new_user_narrative.onebox.not_found'))
          expect(narrative.get_data(user)[:state].to_sym).to eq(:tutorial_onebox)
        end
      end

      describe "when user has not liked bot's post" do
        it 'should create the right reply' do
          narrative.expects(:enqueue_timeout_job).with(user)
          narrative.input(:reply, user, post)
          new_post = Post.last

          expect(new_post.raw).to eq(I18n.t('discourse_narrative_bot.new_user_narrative.onebox.not_found'))
          expect(narrative.get_data(user)[:state].to_sym).to eq(:tutorial_onebox)
        end
      end

      it 'should create the right reply' do
        post.update!(raw: 'https://en.wikipedia.org/wiki/ROT13')

        narrative.expects(:enqueue_timeout_job).with(user)
        narrative.input(:reply, user, post)
        new_post = Post.last

        expected_raw = <<~RAW
          #{I18n.t('discourse_narrative_bot.new_user_narrative.onebox.reply')}

          #{I18n.t('discourse_narrative_bot.new_user_narrative.emoji.instructions')}
        RAW

        expect(new_post.raw).to eq(expected_raw.chomp)
        expect(narrative.get_data(user)[:state].to_sym).to eq(:tutorial_emoji)
      end
    end

    describe 'images tutorial' do
      let(:post_2) { Fabricate(:post, topic: topic) }

      before do
        narrative.set_data(user,
          state: :tutorial_images,
          topic_id: topic.id,
          last_post_id: post_2.id,
          track: described_class.to_s
        )
      end

      describe 'when post is not in the right topic' do
        it 'should not do anything' do
          other_post
          narrative.expects(:enqueue_timeout_job).with(user).never

          expect { narrative.input(:reply, user, other_post) }.to_not change { Post.count }
          expect(narrative.get_data(user)[:state].to_sym).to eq(:tutorial_images)
        end
      end

      it 'should create the right replies' do
        narrative.expects(:enqueue_timeout_job).with(user)
        narrative.input(:reply, user, post)

        expect(Post.last.raw).to eq(I18n.t('discourse_narrative_bot.new_user_narrative.images.not_found'))
        expect(narrative.get_data(user)[:state].to_sym).to eq(:tutorial_images)

        post.update!(
          raw: "<img src='https://i.ytimg.com/vi/tntOCGkgt98/maxresdefault.jpg'>",
        )

        narrative.expects(:enqueue_timeout_job).with(user)
        narrative.input(:reply, user, post)

        expect(Post.last.raw).to eq(I18n.t(
          'discourse_narrative_bot.new_user_narrative.images.like_not_found',
          url: post_2.url
        ))

        expect(narrative.get_data(user)[:state].to_sym).to eq(:tutorial_images)

        expect(narrative.get_data(user)[:tutorial_images][:post_id])
          .to eq(post.id)

        PostAction.act(user, post_2, PostActionType.types[:like])

        expected_raw = <<~RAW
          #{I18n.t('discourse_narrative_bot.new_user_narrative.images.reply')}

          #{I18n.t(
            'discourse_narrative_bot.new_user_narrative.flag.instructions',
            guidelines_url: Discourse.base_url + '/guidelines',
            about_url: Discourse.base_url + '/about'
          )}
        RAW

        post_action = PostAction.last

        expect(post_action.post_action_type_id).to eq(PostActionType.types[:like])
        expect(post_action.user).to eq(described_class.discobot_user)
        expect(post_action.post).to eq(post)
        expect(Post.last.raw).to eq(expected_raw.chomp)
        expect(narrative.get_data(user)[:state].to_sym).to eq(:tutorial_flag)
      end
    end

    describe 'fomatting tutorial' do
      before do
        narrative.set_data(user, state: :tutorial_formatting, topic_id: topic.id)
      end

      describe 'when post is not in the right topic' do
        it 'should not do anything' do
          other_post
          narrative.expects(:enqueue_timeout_job).with(user).never

          expect { narrative.input(:reply, user, other_post) }.to_not change { Post.count }
          expect(narrative.get_data(user)[:state].to_sym).to eq(:tutorial_formatting)
        end
      end

      describe 'when post does not contain any formatting' do
        it 'should create the right reply' do
          narrative.expects(:enqueue_timeout_job).with(user)
          narrative.input(:reply, user, post)

          expect(Post.last.raw).to eq(I18n.t('discourse_narrative_bot.new_user_narrative.formatting.not_found'))
          expect(narrative.get_data(user)[:state].to_sym).to eq(:tutorial_formatting)
        end
      end

      ["**bold**", "__italic__", "[b]bold[/b]", "[i]italic[/i]"].each do |raw|
        it 'should create the right reply' do
          post.update!(raw: raw)

          narrative.expects(:enqueue_timeout_job).with(user)
          narrative.input(:reply, user, post)
          new_post = Post.last

          expected_raw = <<~RAW
            #{I18n.t('discourse_narrative_bot.new_user_narrative.formatting.reply')}

            #{I18n.t('discourse_narrative_bot.new_user_narrative.quoting.instructions')}
          RAW

          expect(new_post.raw).to eq(expected_raw.chomp)
          expect(narrative.get_data(user)[:state].to_sym).to eq(:tutorial_quote)
        end
      end
    end

    describe 'quote tutorial' do
      before do
        narrative.set_data(user, state: :tutorial_quote, topic_id: topic.id)
      end

      describe 'when post is not in the right topic' do
        it 'should not do anything' do
          other_post
          narrative.expects(:enqueue_timeout_job).with(user).never

          expect { narrative.input(:reply, user, other_post) }.to_not change { Post.count }
          expect(narrative.get_data(user)[:state].to_sym).to eq(:tutorial_quote)
        end
      end

      describe 'when post does not contain any quotes' do
        it 'should create the right reply' do
          narrative.expects(:enqueue_timeout_job).with(user)
          narrative.input(:reply, user, post)

          expect(Post.last.raw).to eq(I18n.t('discourse_narrative_bot.new_user_narrative.quoting.not_found'))
          expect(narrative.get_data(user)[:state].to_sym).to eq(:tutorial_quote)
        end
      end

      it 'should create the right reply' do
        post.update!(
          raw: '[quote="#{post.user}, post:#{post.post_number}, topic:#{topic.id}"]\n:monkey: :fries:\n[/quote]'
        )

        narrative.expects(:enqueue_timeout_job).with(user)
        narrative.input(:reply, user, post)
        new_post = Post.last

        expected_raw = <<~RAW
          #{I18n.t('discourse_narrative_bot.new_user_narrative.quoting.reply')}

          #{I18n.t('discourse_narrative_bot.new_user_narrative.images.instructions')}
        RAW

        expect(new_post.raw).to eq(expected_raw.chomp)
        expect(narrative.get_data(user)[:state].to_sym).to eq(:tutorial_images)
      end
    end

    describe 'when [:tutorial_emoji, :reply]' do
      before do
        narrative.set_data(user, state: :tutorial_emoji, topic_id: topic.id)
      end

      describe 'when post is not in the right topic' do
        it 'should not do anything' do
          other_post
          narrative.expects(:enqueue_timeout_job).with(user).never

          expect { narrative.input(:reply, user, other_post) }.to_not change { Post.count }
          expect(narrative.get_data(user)[:state].to_sym).to eq(:tutorial_emoji)
        end
      end

      describe 'when post does not contain any emoji' do
        it 'should create the right reply' do
          narrative.expects(:enqueue_timeout_job).with(user)
          narrative.input(:reply, user, post)

          expect(Post.last.raw).to eq(I18n.t('discourse_narrative_bot.new_user_narrative.emoji.not_found'))
          expect(narrative.get_data(user)[:state].to_sym).to eq(:tutorial_emoji)
        end
      end

      it 'should create the right reply' do
        post.update!(
          raw: ':monkey: :fries:'
        )

        narrative.expects(:enqueue_timeout_job).with(user)
        narrative.input(:reply, user, post)
        new_post = Post.last

        expected_raw = <<~RAW
          #{I18n.t('discourse_narrative_bot.new_user_narrative.emoji.reply')}

          #{I18n.t('discourse_narrative_bot.new_user_narrative.mention.instructions',
            discobot_username: discobot_user.username
          )}
        RAW

        expect(new_post.raw).to eq(expected_raw.chomp)
        expect(narrative.get_data(user)[:state].to_sym).to eq(:tutorial_mention)
      end
    end

    describe 'mention tutorial' do
      before do
        narrative.set_data(user, state: :tutorial_mention, topic_id: topic.id)
      end

      describe 'when post is not in the right topic' do
        it 'should not do anything' do
          other_post
          narrative.expects(:enqueue_timeout_job).with(user).never

          expect { narrative.input(:reply, user, other_post) }.to_not change { Post.count }
          expect(narrative.get_data(user)[:state].to_sym).to eq(:tutorial_mention)
        end
      end

      describe 'when post does not contain any mentions' do
        it 'should create the right reply' do
          narrative.expects(:enqueue_timeout_job).with(user)
          narrative.input(:reply, user, post)

          expect(Post.last.raw).to eq(I18n.t(
            'discourse_narrative_bot.new_user_narrative.mention.not_found',
            username: user.username,
            discobot_username: discobot_user.username
          ))

          expect(narrative.get_data(user)[:state].to_sym).to eq(:tutorial_mention)
        end
      end

      it 'should create the right reply' do
        post.update!(
          raw: '@discobot hello how are you doing today?'
        )

        narrative.expects(:enqueue_timeout_job).with(user)
        narrative.input(:reply, user, post)
        new_post = Post.last

        expected_raw = <<~RAW
          #{I18n.t('discourse_narrative_bot.new_user_narrative.mention.reply')}

          #{I18n.t(
            'discourse_narrative_bot.new_user_narrative.formatting.instructions'
          )}
        RAW

        expect(new_post.raw).to eq(expected_raw.chomp)
        expect(narrative.get_data(user)[:state].to_sym).to eq(:tutorial_formatting)
      end
    end

    describe 'flag tutorial' do
      let(:post) { Fabricate(:post, user: described_class.discobot_user, topic: topic) }
      let(:flag) { Fabricate(:flag, post: post, user: user) }
      let(:other_post) { Fabricate(:post, user: user, topic: topic) }

      before do
        flag
        narrative.set_data(user, state: :tutorial_flag, topic_id: topic.id)
      end

      describe 'when post flagged is not for the right topic' do
        it 'should not do anything' do
          narrative.expects(:enqueue_timeout_job).with(user).never
          flag.update!(post: other_post)

          expect { narrative.input(:flag, user, flag.post) }.to_not change { Post.count }
          expect(narrative.get_data(user)[:state].to_sym).to eq(:tutorial_flag)
        end
      end

      describe 'when post being flagged does not belong to discobot ' do
        it 'should not do anything' do
          narrative.expects(:enqueue_timeout_job).with(user).never
          flag.update!(post: other_post)

          expect { narrative.input(:flag, user, flag.post) }.to_not change { Post.count }
          expect(narrative.get_data(user)[:state].to_sym).to eq(:tutorial_flag)
        end
      end

      describe 'when user replies to the topic' do
        it 'should create the right reply' do
          narrative.input(:reply, user, other_post)
          new_post = Post.last

          expect(new_post.raw).to eq(I18n.t('discourse_narrative_bot.new_user_narrative.flag.not_found'))
          expect(narrative.get_data(user)[:state].to_sym).to eq(:tutorial_flag)
        end
      end

      it 'should create the right reply' do
        narrative.expects(:enqueue_timeout_job).with(user)

        expect  { narrative.input(:flag, user, flag.post) }.to change { PostAction.count }.by(-1)

        new_post = Post.last

        expected_raw = <<~RAW
          #{I18n.t('discourse_narrative_bot.new_user_narrative.flag.reply')}

          #{I18n.t(
            'discourse_narrative_bot.new_user_narrative.search.instructions',
            topic_id: welcome_topic.id, slug: welcome_topic.slug
          )}
        RAW

        expect(new_post.raw).to eq(expected_raw.chomp)
        expect(narrative.get_data(user)[:state].to_sym).to eq(:tutorial_search)
      end
    end

    describe 'search tutorial' do
      before do
        narrative.set_data(user, state: :tutorial_search, topic_id: topic.id)
      end

      describe 'when post is not in the right topic' do
        it 'should not do anything' do
          other_post
          narrative.expects(:enqueue_timeout_job).with(user).never

          expect { narrative.input(:reply, user, other_post) }.to_not change { Post.count }
          expect(narrative.get_data(user)[:state].to_sym).to eq(:tutorial_search)
        end
      end

      describe 'when post does not contain the right answer' do
        it 'should create the right reply' do
          narrative.expects(:enqueue_timeout_job).with(user)
          narrative.input(:reply, user, post)

          expect(Post.last.raw).to eq(I18n.t(
            'discourse_narrative_bot.new_user_narrative.search.not_found'
          ))

          expect(narrative.get_data(user)[:state].to_sym).to eq(:tutorial_search)
        end
      end

      describe 'when post contain the right answer' do
        before do
          PostRevisor.new(first_post, topic).revise!(
            described_class.discobot_user,
            { raw: 'something funny' },
            { skip_validations: true, force_new_version: true }
          )

          narrative.set_data(user,
            state: :tutorial_search,
            topic_id: topic.id,
            tutorial_search: { post_version: first_post.version }
          )
        end

        it 'should create the right reply' do
          post.update!(
            raw: "#{described_class::SEARCH_ANSWER} this is a capybara"
          )

          expect { narrative.input(:reply, user, post) }.to change { Post.count }.by(2)
          new_post = Post.offset(1).last

          expect(new_post.raw).to eq(I18n.t(
            'discourse_narrative_bot.new_user_narrative.search.reply',
            search_url: "#{Discourse.base_url}/search"
          ).chomp)

          expect(first_post.reload.raw).to eq('Hello world')
          
          expect(narrative.get_data(user)).to eq({
            "state" => "end",
            "topic_id" => new_post.topic_id,
            "track" => described_class.to_s
          })
        end
      end
    end
  end
end
