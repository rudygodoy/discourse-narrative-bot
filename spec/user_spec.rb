require 'rails_helper'

describe User do
  let(:user) { Fabricate(:user) }
  let(:profile_page_url) { "#{Discourse.base_url}/users/#{user.username}" }

  describe 'when a user is created' do
    it 'should initiate the bot' do
      Timecop.freeze(Time.new(2016, 10, 31, 16, 30)) do
        user

        expected_raw = I18n.t('discourse_narrative_bot.new_user_narrative.hello.message_1',
          username: user.username, title: SiteSetting.title
        )

        expect(Post.last.raw).to include(expected_raw.chomp)
      end
    end

    context 'when welcome post is disabled' do
      before do
        @original_value = SiteSetting.disable_discourse_narrative_bot_welcome_post
        SiteSetting.disable_discourse_narrative_bot_welcome_post = true
      end

      after do
        SiteSetting.disable_discourse_narrative_bot_welcome_post = @original_value
      end

      it 'should not initiate the bot' do
        expect { user }.to_not change { Post.count }
      end
    end
  end

  describe 'when a user has been destroyed' do
    it "should clean up plugin's store" do
      DiscourseNarrativeBot::Store.set(user.id, 'test')

      user.destroy!

      expect(DiscourseNarrativeBot::Store.get(user.id)).to eq(nil)
    end
  end
end
