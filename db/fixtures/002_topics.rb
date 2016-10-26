staff = Category.find_by(id: SiteSetting.staff_category_id)

if SiteSetting.discobot_welcome_topic_id == -1
  post = PostCreator.create!(
    User.find(-2),
    raw: I18n.t('discourse_narrative_bot.narratives.welcome_topic_body'),
    title: I18n.t('discourse_narrative_bot.narratives.welcome_topic_title'),
    skip_validations: true,
    category: staff ? staff.name : nil
  )

  SiteSetting.discobot_welcome_topic_id = post.topic.id
end
