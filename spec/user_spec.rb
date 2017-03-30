require 'rails_helper'

describe User do
  let(:user) { Fabricate(:user) }
  let(:profile_page_url) { "#{Discourse.base_url}/users/#{user.username}" }

  describe 'when a user is created' do
    it 'should initiate the bot' do
      user

      expected_raw = I18n.t('discourse_narrative_bot.new_user_narrative.hello.message',
        username: user.username, title: SiteSetting.title
      )

      expect(Post.last.raw).to include(expected_raw.chomp)
    end

    context 'when welcome post is disabled' do
      before do
        SiteSetting.disable_discourse_narrative_bot_welcome_post = true
      end

      it 'should not initiate the bot' do
        expect { user }.to_not change { Post.count }
      end
    end

    context 'when user is staged' do
      let(:user) { Fabricate(:user, staged: true) }

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
