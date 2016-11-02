require 'rails_helper'

describe User do
  let(:user) { Fabricate(:user) }

  describe 'when a user is created' do
    it 'should initiate the bot' do
      Timecop.freeze(Time.new(2016, 10, 31, 16, 30)) do
        user

        expected_raw = I18n.t('discourse_narrative_bot.new_user_narrative.hello.message_1',
          username: user.username, title: SiteSetting.title
        )

        expected_raw = <<~RAW
        #{expected_raw}

        #{I18n.t('discourse_narrative_bot.new_user_narrative.hello.triggers')}
        RAW

        expect(Post.last.raw).to eq(expected_raw.chomp)
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
