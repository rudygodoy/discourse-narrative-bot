require 'rails_helper'

describe "Discobot Certificate" do
  let(:user) { Fabricate(:user, name: 'Jeff Atwood') }

  describe 'when viewing the certificate' do
    describe 'when params are missing' do
      it "should raise the right errors" do
        params = {
          name: user.name,
          date: Time.zone.now.strftime("%b %d %Y"),
          avatar_url: 'https://somesite.com/someavatar'
        }

        params.each do |key, _|
          expect { xhr :get, '/discobot/certificate.svg', params.except(key) }
            .to raise_error(Discourse::InvalidParameters)
        end
      end
    end
  end
end
