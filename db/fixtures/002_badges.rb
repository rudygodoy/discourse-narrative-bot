Badge
  .where(name: 'Complete New User Track')
  .update_all(name: DiscourseNarrativeBot::NewUserNarrative::BADGE_NAME)

Badge
  .where(name: 'Complete Discobot Advanced User Track')
  .update_all(name: DiscourseNarrativeBot::AdvancedUserNarrative::BADGE_NAME)

new_user_narrative_badge = Badge.find_by(name: DiscourseNarrativeBot::NewUserNarrative::BADGE_NAME)

unless new_user_narrative_badge
  new_user_narrative_badge = Badge.create!(
    name: DiscourseNarrativeBot::NewUserNarrative::BADGE_NAME,
    description: "Completed Discourse narrative bot's new user track",
    badge_type_id: 3
  )
end

advanced_user_narrative_badge = Badge.find_by(name: DiscourseNarrativeBot::AdvancedUserNarrative::BADGE_NAME)

unless advanced_user_narrative_badge
  advanced_user_narrative_badge = Badge.create!(
    name: DiscourseNarrativeBot::AdvancedUserNarrative::BADGE_NAME,
    description: "Completed Discourse narrative bot's advanced user track",
    badge_type_id: 2
  )
end

[new_user_narrative_badge, advanced_user_narrative_badge].each do |badge|
  badge.update!(badge_grouping: BadgeGrouping.find(1))
end
