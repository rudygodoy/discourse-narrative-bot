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
        username: user.username, reset_trigger: described_class::RESET_TRIGGER
      ))
    end
  end

  describe '#input' do
    before do
      SiteSetting.title = "This is an awesome site!"
      DiscourseNarrativeBot::Store.set(user.id, state: :begin)
    end

    describe 'when an error occurs' do
      before do
        DiscourseNarrativeBot::Store.set(user.id, state: :tutorial_link, topic_id: topic.id)
      end

      it 'should revert to the previous state' do
        narrative.expects(:send).with('init_tutorial_search').raises(StandardError.new('some error'))
        narrative.expects(:send).with(:reply_to_link).returns(post)

        expect { narrative.input(:reply, user, post) }.to raise_error(StandardError, 'some error')
        expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:tutorial_link)
      end
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
      before do
        DiscourseNarrativeBot::Store.set(user.id, state: :begin)
      end

      it 'should raise the right error' do
        expect(narrative.input(:something, user, post)).to eq(nil)
        expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:begin)
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
      let(:profile_page_url) { "#{Discourse.base_url}/users/#{user.username}" }

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

            #{I18n.t('discourse_narrative_bot.new_user_narrative.bookmark.instructions', profile_page_url: profile_page_url)}
          RAW

          expect(new_post.raw).to eq(expected_raw.chomp)

          data = DiscourseNarrativeBot::Store.get(user.id)

          expect(data[:state].to_sym).to eq(:tutorial_bookmark)
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

            #{I18n.t('discourse_narrative_bot.new_user_narrative.bookmark.instructions', profile_page_url: profile_page_url)}
          RAW

          expect(new_post.raw).to eq(expected_raw.chomp)

          data = DiscourseNarrativeBot::Store.get(user.id)

          expect(data[:state].to_sym).to eq(:tutorial_bookmark)
          expect(data[:last_post_id]).to eq(new_post.id)
        end
      end
    end

    describe "bookmark tutorial" do
      before do
        DiscourseNarrativeBot::Store.set(user.id, state: :tutorial_bookmark, topic_id: topic.id)
      end

      describe 'when post is not in the right topic' do
        it 'should not do anything' do
          other_post.update_attributes!(user_id: -2)
          narrative.expects(:enqueue_timeout_job).with(user).never

          expect { narrative.input(:bookmark, user, other_post) }.to_not change { Post.count }
          expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:tutorial_bookmark)
        end
      end

      describe "when bookmark is not on bot's post" do
        it 'should not do anything' do
          narrative.expects(:enqueue_timeout_job).with(user).never
          post

          expect { narrative.input(:bookmark, user, post) }.to_not change { Post.count }
          expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:tutorial_bookmark)
        end
      end

      it 'should create the right reply' do
        post.update_attributes!(user: described_class.discobot_user)
        narrative.expects(:enqueue_timeout_job).with(user)

        narrative.input(:bookmark, user, post)
        new_post = Post.last
        profile_page_url = "#{Discourse.base_url}/users/#{user.username}"

        expected_raw = <<~RAW
          #{I18n.t('discourse_narrative_bot.new_user_narrative.bookmark.reply', profile_page_url: profile_page_url)}

          #{I18n.t('discourse_narrative_bot.new_user_narrative.onebox.instructions')}
        RAW

        expect(new_post.raw).to eq(expected_raw.chomp)
        expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:tutorial_onebox)
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

      describe "when user has not liked bot's post" do
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

    describe 'images tutorial' do
      let(:post_2) { Fabricate(:post, topic: topic) }

      before do
        DiscourseNarrativeBot::Store.set(user.id,
          state: :tutorial_images, topic_id: topic.id, last_post_id: post_2.id
        )
      end

      describe 'when post is not in the right topic' do
        it 'should not do anything' do
          other_post
          narrative.expects(:enqueue_timeout_job).with(user).never

          expect { narrative.input(:reply, user, other_post) }.to_not change { Post.count }
          expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:tutorial_images)
        end
      end

      it 'should create the right replies' do
        narrative.expects(:enqueue_timeout_job).with(user)
        narrative.input(:reply, user, post)

        expect(Post.last.raw).to eq(I18n.t('discourse_narrative_bot.new_user_narrative.images.not_found'))
        expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:tutorial_images)

        post.update_attributes!(
          raw: "<img src='https://i.ytimg.com/vi/tntOCGkgt98/maxresdefault.jpg'>",
        )

        narrative.expects(:enqueue_timeout_job).with(user)
        narrative.input(:reply, user, post)

        expect(Post.last.raw).to eq(I18n.t(
          'discourse_narrative_bot.new_user_narrative.images.like_not_found',
          url: post_2.url
        ))

        expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:tutorial_images)

        expect(DiscourseNarrativeBot::Store.get(user.id)[:tutorial_images][:post_id])
          .to eq(post.id)

        PostAction.act(user, post_2, PostActionType.types[:like])

        expected_raw = <<~RAW
          #{I18n.t('discourse_narrative_bot.new_user_narrative.images.reply')}

          #{I18n.t('discourse_narrative_bot.new_user_narrative.formatting.instructions')}
        RAW

        post_action = PostAction.last

        expect(post_action.post_action_type_id).to eq(PostActionType.types[:like])
        expect(post_action.user).to eq(described_class.discobot_user)
        expect(post_action.post).to eq(post)
        expect(Post.last.raw).to eq(expected_raw.chomp)
        expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:tutorial_formatting)
      end
    end

    describe 'fomatting tutorial' do
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

      ["**bold**", "__italic__", "[b]bold[/b]", "[i]italic[/i]"].each do |raw|
        it 'should create the right reply' do
          post.update_attributes!(raw: raw)

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
            guidelines_url: Discourse.base_url + '/guidelines',
            about_url: Discourse.base_url + '/about'
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

    describe 'link tutorial' do
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

      describe 'when post does not contain any links' do
        it 'should create the right reply' do
          narrative.expects(:enqueue_timeout_job).with(user)
          narrative.input(:reply, user, post)

          expect(Post.last.raw).to eq(I18n.t(
            'discourse_narrative_bot.new_user_narrative.link.not_found',
            topic_id: welcome_topic.id, slug: welcome_topic.slug
          ))

          store = DiscourseNarrativeBot::Store.get(user.id)

          expect(store[:state].to_sym).to eq(:tutorial_link)
        end
      end

      it 'should create the right reply' do
        pending "somehow it isn't oneboxed in tests"

        post.update_attributes!(
          raw: "https://#{Discourse.current_hostname}/t/something-to-say/485"
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
        expect(store[:tutorial_search][:post_version]).to eq(2)
      end
    end

    describe 'search tutorial' do
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
        before do
          PostRevisor.new(first_post, topic).revise!(
            described_class.discobot_user,
            { raw: 'something funny' },
            { skip_validations: true, force_new_version: true }
          )

          DiscourseNarrativeBot::Store.set(user.id,
            state: :tutorial_search,
            topic_id: topic.id,
            tutorial_search: { post_version: first_post.version }
          )
        end

        it 'should create the right reply' do
          post.update_attributes!(
            raw: "#{described_class::SEARCH_ANSWER} this is a capybara"
          )

          expect { narrative.input(:reply, user, post) }.to change { Post.count }.by(2)
          new_post = Post.offset(1).last

          expect(new_post.raw).to eq(I18n.t(
            'discourse_narrative_bot.new_user_narrative.search.reply',
            search_url: "#{Discourse.base_url}/search"
          ).chomp)

          expect(first_post.reload.raw).to eq('Hello world')
          expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:end)
        end
      end
    end

    describe ':end state' do
      before do
        DiscourseNarrativeBot::Store.set(user.id, state: :end, topic_id: topic.id)
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
          'discourse_narrative_bot.new_user_narrative.do_not_understand.first_response',
          reset_trigger: described_class::RESET_TRIGGER
        ))

        expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:end)

        narrative.input(:reply, user, Fabricate(:post,
          topic: topic,
          user: user,
          reply_to_post_number: Post.last.post_number
        ))

        expect(Post.last.raw).to eq(I18n.t(
          'discourse_narrative_bot.new_user_narrative.do_not_understand.second_response',
          reset_trigger: described_class::RESET_TRIGGER
        ))

        expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:end)

        new_post = Fabricate(:post,
          topic: topic,
          user: user,
          reply_to_post_number: Post.last.post_number
        )

        expect { narrative.input(:reply, user, new_post) }.to_not change { Post.count }

        expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:end)

        new_post = Fabricate(:post,
          topic: topic,
          user: user,
          raw: "@discobot hello!"
        )

        narrative.input(:reply, user, new_post)

        expect(DiscourseNarrativeBot::Store.get(user.id)[:state].to_sym).to eq(:end)

        expect(Post.last.raw).to eq(
          I18n.t("discourse_narrative_bot.new_user_narrative.random_mention.message")
        )
      end
    end

    describe 'pms to discobot' do
      let(:other_topic) do
        topic_allowed_user = Fabricate.build(:topic_allowed_user, user: user)
        bot = Fabricate.build(:topic_allowed_user, user: described_class.discobot_user)

        Fabricate(:private_message_topic, topic_allowed_users: [topic_allowed_user, bot])
      end

      describe 'when a new message is made' do
        it 'should create the right reply' do
          post = Fabricate(:post, topic: other_topic)

          narrative.input(:reply, user, post)

          expect(Post.last.raw).to eq(
            I18n.t("discourse_narrative_bot.new_user_narrative.random_mention.message")
          )
        end
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
            other_post.update_attributes!(raw: '@discobot roll 2d1')
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
