unless Rails.env.test?
  category = Category.find_by(id: ENV['BOT_CATEGORY_ID'] || SiteSetting.staff_category_id)
  SiteSetting.discobot_category_id = category.id

  create_post =
    if SiteSetting.discobot_welcome_topic_id == -1
      true
    else
      category.topics.where(id: SiteSetting.discobot_welcome_topic_id).empty?
    end

  if create_post
    post = PostCreator.create!(
      User.find(-2),
      raw: I18n.t('discourse_narrative_bot.narratives.welcome_topic_body', category_slug: category.slug),
      title: I18n.t('discourse_narrative_bot.narratives.welcome_topic_title'),
      skip_validations: true,
      pinned_at: Time.zone.now,
      pinned_globally: true,
      category: category ? category.name : nil
    )

    SiteSetting.discobot_welcome_topic_id = post.topic.id
  end
end
