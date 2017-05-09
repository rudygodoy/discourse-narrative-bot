unless Badge.find_by(name: DiscourseNarrativeBot::NewUserNarrative::BADGE_NAME)
  Badge.create!(
    name: DiscourseNarrativeBot::NewUserNarrative::BADGE_NAME,
    description: "Completed Discourse narrative bot's new user track",
    badge_type_id: 3
  )
end

unless Badge.find_by(name: DiscourseNarrativeBot::AdvancedUserNarrative::BADGE_NAME)
  Badge.create!(
    name: DiscourseNarrativeBot::AdvancedUserNarrative::BADGE_NAME,
    description: "Completed Discourse narrative bot's advanced user track",
    badge_type_id: 2
  )
end
