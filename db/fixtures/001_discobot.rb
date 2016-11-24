discobot_username ='discobot'
user = User.find_by("id <> -2 and username_lower = '#{discobot_username}'")

if user
  user.update_attributes!(username: UserNameSuggester.suggest(discobot_username))
end

User.seed do |u|
  u.id = -2
  u.name = discobot_username
  u.username = discobot_username
  u.username_lower = discobot_username
  u.email = "discobot_email"
  u.password = SecureRandom.hex
  u.active = true
  u.admin = true
  u.moderator = true
  u.approved = true
  u.trust_level = TrustLevel[4]
end

bot = User.find(-2)

bot.user_option.update_attributes!(
  email_private_messages: false,
  email_direct: false
)

if !bot.user_profile.bio_raw
  bot.user_profile.update_attributes!(
    bio_raw: I18n.t('discourse_narrative_bot.bio', site_title: SiteSetting.title, discobot_username: bot.username)
  )
end

Group.user_trust_level_change!(-2, TrustLevel[4])

# TODO Pull the user avatar from that thread for now. In the future, pull it from a local file or from some central discobot repo.
UserAvatar.import_url_for_user(
  "https://cdn.discourse.org/dev/uploads/default/original/2X/e/edb63d57a720838a7ce6a68f02ba4618787f2299.png",
  User.find_by(username: discobot_username),
  override_gravatar: true
)
