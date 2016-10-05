PLUGIN_NAME = "discourse-narrative-bot"

# TODO In the future, don't just hijack this guy.
def get_user
  @discobot ||= User.find_by({username: "discobot"})

  unless @discobot
    @discobot = User.create(
      name: "Discobot",
      username: "discobot",
      approved: true, active: true,
      admin: true,
      password: SecureRandom.hex,
      email: "#{SecureRandom.hex}@anon.#{Discourse.current_hostname}",
      trust_level: 4,
      trust_level_locked: true,
      created_at: 10000.years.ago
    )

    @discobot.grant_admin!
    @discobot.activate

    # TODO Pull the user avatar from that thread for now. In the future, pull it from a local file or from some central discobot repo.
    UserAvatar.import_url_for_user(
      "https://cdn.discourse.org/dev/uploads/default/original/2X/e/edb63d57a720838a7ce6a68f02ba4618787f2299.png",
      @discobot,
      override_gravatar: true )
  end
  @discobot
end

# TODO(@nicksahler) Move all of this to an event job
DiscourseEvent.on(:group_user_created) do | group_user |
  Jobs.enqueue(:narrative_input,
    user_id: group_user.user.id,
    narrative: 'staff_introduction',
    input: 'init'
  ) if group_user.group.name === 'staff' && group_user.user.id != get_user.id 
end

DiscourseEvent.on(:post_created) do | post |
  Jobs.enqueue(:narrative_input,
    user_id: post.user.id,
    post_id: post.id,
    narrative: 'staff_introduction',
    input: 'reply'
  )
end

# Staff intro here
# TODO Move to i18n, use that kind of interpolation.

Narrative.create 'staff_introduction' do
  state :begin, on: 'init' do | user |
    title = "I'm Discobot, stop by and say hello!" 
    main_topic = Topic.find_by({slug: Slug.for(title)})
    copy = %Q{Hi @#{user.username}
    
Welcome to #{SiteSetting.title}! It's great to meet you.

I'd :heart: to show you around, if you have time. Just reply to this post to get started.}
    
    if (main_topic != nil)
      data[:topic_id] = main_topic.id
      dirty
    end

    if (data[:topic_id])
      reply get_user, copy
    else
      copy = %Q{
Hey, I'm Discobot!

Don't be alarmed, but I'm not a real person. I'm a robot that helps introduce staff to your site and teaches everyone how it works.

I'll send a brief greeting to each new staff member in this topic, welcoming them to the site and offering them a chance to experiment with me and discover how everything works. There's even a special prize at the end! :gift: Really!

If you'd like to interact with me, just mention @discobot anywhere in the staff category. Otherwise I'll stay out of your way, because I know you're busy.
      }
      data[:topic_id] = ( reply get_user, copy, {
          title: title, 
          category: Category.find_by(slug: 'staff').id
        }
      ).topic.id

      dirty

      reply get_user, copy
    end

    :waiting_quote
  end

  #(I18n.t 'narratives.quote_user', username: post.user.username )
  state :waiting_quote, on: 'reply' do | user, post |
    if data[:topic_id] === post.topic.id
      copy = %Q{Excellent! Let me quote what you just said:

[quote="#{post.user.username}, post:#{post.id}, topic:#{post.topic.id}, full:true"]
#{post.raw}
[/quote]

Did you notice how my reply appeared automatically, without refreshing the page? Everything updates here in real time. :clock:

Next, can you create a new topic in the #staff category and mention any subject I like?

- unicorns
- bacon
- ninjas
- monkeys

(Please don't judge me. I was programmed this way!)
}

      reply get_user, copy

      # post.topic.update_status( :closed, true, get_user )

      :waiting_user_newtopic
    end
  end

  EXAMPLES = {
    "unicorn" => "Did you know that the unicorn is Scotland's national animal? :unicorn: \nhttps://en.wikipedia.org/wiki/Unicorn",
    "ninja" => "Did you know that ninjas used to hide in the same spot for days, disguised as inanimate objects like rocks and trees :leaves:? \nhttp://nerdreactor.com/wp-content/uploads/2012/12/Ninja_Gaiden_NES_02.jpg",
    "bacon" => ":pig: :pig: :pig: :pig: :pig: :pig: \nhttps://media.giphy.com/media/10l8MVei2OxbuU/giphy.gif \nhttps://media.giphy.com/media/qZiUOutzxgfKM/giphy.gif",
    "monkey" => ":monkey: :fries: \nhttps://www.youtube.com/watch?v=FjqfX8-L0Tk"
  }

  state :waiting_user_newtopic, on: 'reply' do | user, post |
    if post.topic.category.slug === 'staff' && (subject = /\s*(unicorn)|(bacon)|(ninja)|(monkey)\s*/i.match(post.raw)) && post.topic.id != data[:topic_id]
      data[:topic_id] = post.topic.id
      dirty

      copy = %Q{I'm so glad you started this topic, because I love #{ subject.to_s }!

#{EXAMPLES[subject.to_s.downcase.singularize]}

Can you share any Wikipedia links about #{ subject.to_s }? Try replying with a link on a line by itself, and it'll automatically expand to include a summary.
}

      reply get_user, copy
      :duel
    end
  end

  state :duel, on: 'reply' do | user, post |
    return if data[:topic_id] != post.topic.id
    post.post_analyzer.cook post.raw, {}

    if post.post_analyzer.found_oneboxes?
      :end # TODO something else later? 
    else
      reply get_user, "That does not have a onebox in it! Paste a link to something on its own line to onebox something."
    end
  end
# TODO Maybe move this to another file to declutter. Also gzip or something before posting. Sory 4 long line  
  state :end do | user |
    reply get_user, %Q{Wow, good job! I think after all of that you deserve an award! I made this for you for your achievements: 
<img src='data:image/svg+xml;utf8,<?xml version="1.0" encoding="utf-8"?> <!-- Generator: Adobe Illustrator 19.1.1, SVG Export Plug-In . SVG Version: 6.00 Build 0) --> <svg version="1.1" id="Layer_1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" x="0px" y="0px" viewBox="0 0 792 612" style="enable-background:new 0 0 792 612;" xml:space="preserve"> <style type="text/css"> .st0{clip-path:url(#SVGID_2_);fill:#FFF1CC;} .st1{clip-path:url(#SVGID_2_);fill:#FFF1CD;} .st2{clip-path:url(#SVGID_2_);fill:#FFF1CE;} .st3{clip-path:url(#SVGID_2_);fill:#FFF2CE;} .st4{clip-path:url(#SVGID_2_);fill:#FFF2CF;} .st5{clip-path:url(#SVGID_2_);fill:#FFF2D0;} .st6{clip-path:url(#SVGID_2_);fill:#FFF2D1;} .st7{clip-path:url(#SVGID_2_);fill:#FFF3D1;} .st8{clip-path:url(#SVGID_2_);fill:#FFF3D2;} .st9{clip-path:url(#SVGID_2_);fill:#FFF3D3;} .st10{clip-path:url(#SVGID_2_);fill:#FFF3D4;} .st11{clip-path:url(#SVGID_2_);fill:#FFF4D5;} .st12{clip-path:url(#SVGID_2_);fill:#FFF4D6;} .st13{clip-path:url(#SVGID_2_);fill:#FFF4D7;} .st14{clip-path:url(#SVGID_2_);fill:#FFF4D8;} .st15{clip-path:url(#SVGID_2_);fill:#FFF5D9;} .st16{clip-path:url(#SVGID_2_);fill:#FFF5DA;} .st17{clip-path:url(#SVGID_2_);fill:#FFF5DB;} .st18{clip-path:url(#SVGID_2_);fill:#FFF5DC;} .st19{clip-path:url(#SVGID_2_);fill:#FFF6DE;} .st20{clip-path:url(#SVGID_2_);fill:#FFF6DF;} .st21{clip-path:url(#SVGID_2_);fill:#FFF6E0;} .st22{clip-path:url(#SVGID_2_);fill:#FFF7E1;} .st23{clip-path:url(#SVGID_2_);fill:#FFF7E3;} .st24{clip-path:url(#SVGID_2_);fill:#FFF8E4;} .st25{clip-path:url(#SVGID_2_);fill:#FFF8E5;} .st26{clip-path:url(#SVGID_2_);fill:#FFF8E7;} .st27{clip-path:url(#SVGID_2_);fill:#FFF9E8;} .st28{clip-path:url(#SVGID_2_);fill:#FFF9EA;} .st29{clip-path:url(#SVGID_2_);fill:#FFFAEB;} .st30{clip-path:url(#SVGID_2_);fill:#FFFAED;} .st31{clip-path:url(#SVGID_2_);fill:#FFFAEF;} .st32{clip-path:url(#SVGID_2_);fill:#FFFBF0;} .st33{clip-path:url(#SVGID_2_);fill:#FFFBF2;} .st34{clip-path:url(#SVGID_2_);fill:#FFFCF4;} .st35{clip-path:url(#SVGID_2_);fill:#FFFCF5;} .st36{clip-path:url(#SVGID_2_);fill:#FFFDF7;} .st37{clip-path:url(#SVGID_2_);fill:#FFFDF9;} .st38{clip-path:url(#SVGID_2_);fill:#FFFEFB;} .st39{clip-path:url(#SVGID_2_);fill:#FFFEFD;} .st40{clip-path:url(#SVGID_2_);fill:#FFFFFF;} .st41{fill:none;} .st42{font-family: Sans-Serif;} .st43{font-size:30px;} .st44{font-size:80px;} .st45{font-size:20px;} .st46{fill:#EAD053;} </style> <font horiz-adv-x="1000"> <!-- Copyright 1992, 1994, 1997, 2000, 2004 Adobe Systems Incorporated. All rights reserved. Myriad is either a registered trademark or a trademark of Adobe Systems Incorporated in the United States and/or other countries. --> <font-face font-family="MyriadPro-Regular" units-per-em="1000" underline-position="-100" underline-thickness="50"/> <missing-glyph horiz-adv-x="500" d="M0,0l500,0l0,700l-500,0M250,395l-170,255l340,0M280,350l170,255l0,-510M80,50l170,255l170,-255M50,605l170,-255l-170,-255z"/> <glyph unicode="A" horiz-adv-x="612" d="M424,212l72,-212l93,0l-230,674l-105,0l-229,-674l90,0l70,212M203,280l66,195C282,516 293,557 303,597l2,0C315,558 325,518 340,474l66,-194z"/> <glyph unicode="C" horiz-adv-x="580" d="M529,91C494,74 440,63 387,63C223,63 128,169 128,334C128,511 233,612 391,612C447,612 494,600 527,584l21,71C525,667 472,685 388,685C179,685 36,542 36,331C36,110 179,-10 369,-10C451,-10 515,6 547,22z"/> <glyph unicode="E" horiz-adv-x="492" d="M425,388l-262,0l0,213l277,0l0,73l-364,0l0,-674l379,0l0,73l-292,0l0,243l262,0z"/> <glyph unicode="G" horiz-adv-x="646" d="M589,354l-222,0l0,-70l137,0l0,-201C484,73 445,65 388,65C231,65 128,166 128,337C128,506 235,608 399,608C467,608 512,595 548,579l21,71C540,664 479,681 401,681C175,681 37,534 36,333C36,228 72,138 130,82C196,19 280,-7 382,-7C473,-7 550,16 589,30z"/> <glyph unicode="M" horiz-adv-x="804" d="M661,0l85,0l-42,674l-111,0l-120,-326C443,263 419,189 402,121l-3,0C382,191 359,265 331,348l-115,326l-111,0l-47,-674l83,0l18,289C165,390 170,503 172,587l2,0C193,507 220,420 252,325l109,-321l66,0l119,327C580,424 608,508 631,587l3,0C633,503 639,390 644,296z"/> <glyph unicode="N" horiz-adv-x="658" d="M158,0l0,288C158,400 156,481 151,566l3,1C188,494 233,417 280,342l214,-342l88,0l0,674l-82,0l0,-282C500,287 502,205 510,115l-2,-1C476,183 437,254 387,333l-216,341l-95,0l0,-674z"/> <glyph unicode="O" horiz-adv-x="689" d="M349,685C169,685 36,545 36,331C36,127 161,-11 339,-11C511,-11 652,112 652,344C652,544 533,685 349,685M345,614C490,614 560,474 560,340C560,187 482,60 344,60C207,60 129,189 129,333C129,481 201,614 345,614z"/> <glyph unicode="P" horiz-adv-x="532" d="M76,0l87,0l0,270C183,265 207,264 233,264C318,264 393,289 439,338C473,373 491,421 491,482C491,542 469,591 432,623C392,659 329,679 243,679C173,679 118,673 76,666M163,603C178,607 207,610 245,610C341,610 404,567 404,478C404,385 340,334 235,334C206,334 182,336 163,341z"/> <glyph unicode="S" horiz-adv-x="493" d="M42,33C78,9 149,-10 214,-10C373,-10 450,80 450,184C450,283 392,338 278,382C185,418 144,449 144,512C144,558 179,613 271,613C332,613 377,593 399,581l24,71C393,669 343,685 274,685C143,685 56,607 56,502C56,407 124,350 234,311C325,276 361,240 361,177C361,109 309,62 220,62C160,62 103,82 64,106z"/> <glyph unicode="T" horiz-adv-x="497" d="M204,0l88,0l0,600l206,0l0,74l-499,0l0,-74l205,0z"/> <glyph unicode="V" horiz-adv-x="558" d="M320,0l241,674l-93,0l-114,-333C324,253 296,168 277,90l-2,0C257,169 232,251 203,342l-105,332l-94,0l220,-674z"/> <glyph unicode="W" horiz-adv-x="846" d="M277,0l96,351C398,438 413,504 425,571l2,0C436,503 450,437 471,351l85,-351l91,0l191,674l-89,0l-89,-340C639,250 620,175 606,101l-2,0C594,172 576,252 557,332l-82,342l-91,0l-90,-340C271,247 250,167 239,100l-2,0C225,165 207,249 187,333l-80,341l-92,0l171,-674z"/> <glyph unicode="a" horiz-adv-x="482" d="M421,0C415,33 413,74 413,116l0,181C413,394 377,495 229,495C168,495 110,478 70,452l20,-58C124,416 171,430 216,430C315,430 326,358 326,318l0,-10C139,309 35,245 35,128C35,58 85,-11 183,-11C252,-11 304,23 331,61l3,0l7,-61M328,163C328,154 326,144 323,135C309,94 269,54 206,54C161,54 123,81 123,138C123,232 232,249 328,247z"/> <glyph unicode="{" horiz-adv-x="284" d="M28,262C99,262 109,219 109,188C109,161 105,134 101,107C97,80 93,52 93,25C93,-76 155,-112 238,-112l21,0l0,55l-18,0C185,-57 162,-26 162,30C162,54 165,77 169,102C173,126 176,151 176,178C177,242 149,276 104,287l0,2C149,301 177,333 176,397C176,424 173,448 169,473C165,497 162,521 162,544C162,598 182,630 241,630l18,0l0,55l-21,0C153,685 93,646 93,554C93,526 97,499 101,471C105,443 109,415 109,387C109,352 99,313 28,313z"/> <glyph unicode="}" horiz-adv-x="284" d="M256,313C185,313 175,352 175,387C175,415 179,443 183,471C187,499 191,526 191,554C191,646 130,685 45,685l-20,0l0,-55l18,0C101,629 122,598 122,544C122,521 118,497 115,473C111,448 107,424 107,397C107,333 135,301 179,289l0,-2C135,276 107,242 107,178C107,151 111,126 115,102C118,77 122,54 122,30C122,-26 98,-56 42,-57l-17,0l0,-55l21,0C128,-112 191,-76 191,25C191,52 187,80 183,107C179,134 175,161 175,188C175,219 185,262 256,262z"/> <glyph unicode="c" horiz-adv-x="448" d="M403,84C378,73 345,60 295,60C199,60 127,129 127,241C127,342 187,424 298,424C346,424 379,413 400,401l20,68C396,481 350,494 298,494C140,494 38,386 38,237C38,89 133,-10 279,-10C344,-10 395,6 418,18z"/> <glyph unicode="," horiz-adv-x="207" d="M79,-117C107,-70 151,41 174,126l-98,-10C65,43 38,-64 16,-123z"/> <glyph unicode="d" horiz-adv-x="564" d="M403,710l0,-289l-2,0C379,460 329,495 255,495C137,495 37,396 38,235C38,88 128,-11 245,-11C324,-11 383,30 410,84l2,0l4,-84l79,0C492,33 491,82 491,125l0,585M403,203C403,189 402,177 399,165C383,99 329,60 270,60C175,60 127,141 127,239C127,346 181,426 272,426C338,426 386,380 399,324C402,313 403,298 403,287z"/> <glyph unicode="e" horiz-adv-x="501" d="M462,226C463,235 465,249 465,267C465,356 423,495 265,495C124,495 38,380 38,234C38,88 127,-10 276,-10C353,-10 406,6 437,20l-15,63C389,69 351,58 288,58C200,58 124,107 122,226M123,289C130,350 169,432 258,432C357,432 381,345 380,289z"/> <glyph unicode="f" horiz-adv-x="292" d="M169,0l0,417l117,0l0,67l-117,0l0,26C169,584 188,650 263,650C288,650 306,645 319,639l12,68C314,714 287,721 256,721C215,721 171,708 138,676C97,637 82,575 82,507l0,-23l-68,0l0,-67l68,0l0,-417z"/> <glyph unicode="g" horiz-adv-x="559" d="M413,484l-4,-73l-2,0C386,451 340,495 256,495C145,495 38,402 38,238C38,104 124,2 244,2C319,2 371,38 398,83l2,0l0,-54C400,-93 334,-140 244,-140C184,-140 134,-122 102,-102l-22,-67C119,-195 183,-209 241,-209C302,-209 370,-195 417,-151C464,-109 486,-41 486,70l0,281C486,410 488,449 490,484M399,206C399,191 397,174 392,159C373,103 324,69 270,69C175,69 127,148 127,243C127,355 187,426 271,426C335,426 378,384 394,333C398,321 399,308 399,293z"/> <glyph unicode="h" horiz-adv-x="555" d="M73,0l88,0l0,292C161,309 162,322 167,334C183,382 228,422 285,422C368,422 397,356 397,278l0,-278l88,0l0,288C485,455 381,495 316,495C283,495 252,485 226,470C199,455 177,433 163,408l-2,0l0,302l-88,0z"/> <glyph unicode="i" horiz-adv-x="234" d="M161,0l0,484l-88,0l0,-484M117,675C85,675 62,651 62,620C62,590 84,566 115,566C150,566 172,590 171,620C171,651 150,675 117,675z"/> <glyph unicode="l" horiz-adv-x="236" d="M73,0l88,0l0,710l-88,0z"/> <glyph unicode="m" horiz-adv-x="834" d="M73,0l86,0l0,292C159,307 161,322 166,335C180,379 220,423 275,423C342,423 376,367 376,290l0,-290l86,0l0,299C462,315 465,331 469,343C484,386 523,423 573,423C644,423 678,367 678,274l0,-274l86,0l0,285C764,453 669,495 605,495C559,495 527,483 498,461C478,446 459,425 444,398l-2,0C421,455 371,495 305,495C225,495 180,452 153,406l-3,0l-4,78l-77,0C72,444 73,403 73,353z"/> <glyph unicode="n" horiz-adv-x="555" d="M73,0l88,0l0,291C161,306 163,321 167,332C182,381 227,422 285,422C368,422 397,357 397,279l0,-279l88,0l0,289C485,455 381,495 314,495C234,495 178,450 154,404l-2,0l-5,80l-78,0C72,444 73,403 73,353z"/> <glyph unicode="#" horiz-adv-x="497" d="M188,255l19,145l104,0l-19,-145M153,0l26,196l104,0l-26,-196l60,0l26,196l95,0l0,59l-86,0l18,145l91,0l0,59l-82,0l25,191l-59,0l-26,-191l-104,0l25,191l-58,0l-26,-191l-95,0l0,-59l86,0l-19,-145l-91,0l0,-59l82,0l-26,-196z"/> <glyph unicode="o" horiz-adv-x="549" d="M278,495C144,495 38,400 38,238C38,85 139,-11 270,-11C387,-11 511,67 511,246C511,394 417,495 278,495M276,429C380,429 421,325 421,243C421,134 358,55 274,55C188,55 127,135 127,241C127,333 172,429 276,429z"/> <glyph unicode="p" horiz-adv-x="569" d="M73,-198l87,0l0,263l2,0C191,17 247,-11 311,-11C425,-11 531,75 531,249C531,396 443,495 326,495C247,495 190,460 154,401l-2,0l-4,83l-79,0C71,438 73,388 73,326M160,280C160,292 163,305 166,316C183,382 239,425 299,425C392,425 443,342 443,245C443,134 389,58 296,58C233,58 180,100 164,161C162,172 160,184 160,197z"/> <glyph unicode="r" horiz-adv-x="327" d="M73,0l87,0l0,258C160,273 162,287 164,299C176,365 220,412 282,412C294,412 303,411 312,409l0,83C304,494 297,495 287,495C228,495 175,454 153,389l-4,0l-3,95l-77,0C72,439 73,390 73,333z"/> <glyph unicode="s" horiz-adv-x="396" d="M39,23C73,3 122,-10 175,-10C290,-10 356,50 356,135C356,207 313,249 229,281C166,305 137,323 137,363C137,399 166,429 218,429C263,429 298,413 317,401l22,64C312,481 269,495 220,495C116,495 53,431 53,353C53,295 94,247 181,216C246,192 271,169 271,127C271,87 241,55 177,55C133,55 87,73 61,90z"/> <glyph unicode=" " horiz-adv-x="212"/> <glyph unicode="t" horiz-adv-x="331" d="M93,600l0,-116l-75,0l0,-67l75,0l0,-264C93,96 102,53 127,27C148,3 181,-10 222,-10C256,-10 283,-5 300,2l-4,66C285,65 268,62 245,62C196,62 179,96 179,156l0,261l126,0l0,67l-126,0l0,139z"/> <glyph unicode="u" horiz-adv-x="551" d="M478,484l-88,0l0,-297C390,171 387,155 382,142C366,103 325,62 266,62C186,62 158,124 158,216l0,268l-88,0l0,-283C70,31 161,-11 237,-11C323,-11 374,40 397,79l2,0l5,-79l78,0C479,38 478,82 478,132z"/> <glyph unicode="v" horiz-adv-x="481" d="M13,484l184,-484l84,0l190,484l-92,0l-94,-272C269,168 255,128 244,88l-3,0C231,128 218,168 202,212l-95,272z"/> <glyph unicode="y" horiz-adv-x="471" d="M9,484l179,-446C192,27 194,20 194,15C194,10 191,3 187,-6C167,-51 137,-85 113,-104C87,-126 58,-140 36,-147l22,-74C80,-217 123,-202 166,-164C226,-112 269,-27 332,139l132,345l-93,0l-96,-284C263,165 253,128 244,99l-2,0C234,128 222,166 211,198l-106,286z"/> </font> <g> <g> <defs> <rect id="SVGID_1_" width="792" height="612"/> </defs> <clipPath id="SVGID_2_"> <use xlink:href="#SVGID_1_" style="overflow:visible;"/> </clipPath> <rect class="st0" width="792" height="612"/> <path class="st0" d="M749.9,306c0,97.7-39.6,186.2-103.6,250.2c-16,16-33.4,30.5-52.2,43.2c-9.4,6.4-19,12.3-29,17.7V613H227v4.2 c-10-5.4-19.6-11.4-29-17.7c-18.8-12.7-36.3-27.2-52.3-43.2c-64-64-103.6-152.5-103.6-250.2S81.7,119.8,145.8,55.8 c16-16,33.4-30.5,52.2-43.2c9.4-6.4,19-12.3,29-17.7V-1h338v-4.2c10,5.4,19.6,11.4,29,17.7c18.8,12.7,36.3,27.2,52.3,43.2 C710.3,119.8,749.9,208.3,749.9,306z"/> <path class="st0" d="M742.9,306c0,95.8-38.8,182.5-101.6,245.3c-15.7,15.7-32.9,29.9-51.3,42.4c-9.2,6.2-19,12-28.8,17.4 c-4.9,2.7-10.2,5.2-15.2,7.7V613H246v5.7c-5-2.4-10.2-5-15.2-7.7c-9.8-5.3-19.5-11.1-28.7-17.4c-18.5-12.5-35.7-26.7-51.4-42.4 C87.9,488.5,49.1,401.8,49.1,306S87.9,123.5,150.7,60.7C166.4,45,183.6,30.8,202,18.3c9.2-6.2,19-12,28.8-17.4 c4.9-2.7,10.2-5.2,15.2-7.7V-1h300v-5.7c5,2.4,10.2,5,15.2,7.7c9.8,5.3,19.5,11.1,28.7,17.4c18.5,12.5,35.7,26.7,51.4,42.4 C704.1,123.5,742.9,210.2,742.9,306z"/> <path class="st0" d="M736,306c0,93.9-38.2,178.9-99.8,240.4c-30.8,30.8-67.2,55.7-108.2,72.9V613H264v6.3 c-41-17.2-77.5-42.1-108.2-72.9C94.2,484.9,56.1,399.9,56.1,306s38.2-178.9,99.7-240.4C186.6,34.8,223,9.9,264-7.3V-1h264v-6.3 c41,17.2,77.5,42.1,108.2,72.9C697.8,127.1,736,212.1,736,306z"/> <path class="st0" d="M729.1,306c0,92-37.3,175.2-97.6,235.5c-30.1,30.1-65.8,54.5-105.6,71.4c-5,2.1-9.9,4.1-14.9,6V613H281v5.8 c-5-1.9-9.9-3.9-14.9-6c-39.8-16.9-75.6-41.2-105.7-71.4C100.1,481.2,62.9,398,62.9,306s37.3-175.2,97.6-235.5 C190.6,40.4,226.3,16,266.1-0.9c5-2.1,9.9-4.1,14.9-6V-1h230v-5.8c5,1.9,9.9,3.9,14.9,6c39.8,16.9,75.6,41.2,105.7,71.4 C691.9,130.8,729.1,214,729.1,306z"/> <path class="st0" d="M722.1,306c0,90.1-36.5,171.6-95.5,230.6C597.1,566.1,562,590,523,606.5c-9.8,4.1-20,7.8-30,11V613H299v4.5 c-10-3.2-20.2-6.8-30-11c-39-16.5-74.1-40.4-103.7-69.9c-59-59-95.5-140.5-95.5-230.6s36.5-171.6,95.5-230.6 C194.9,45.9,230,22,269,5.5c9.8-4.1,20-7.8,30-11V-1h194v-4.5c10,3.2,20.2,6.8,30,11c39,16.5,74.1,40.4,103.7,69.9 C685.6,134.4,722.1,215.9,722.1,306z"/> <path class="st1" d="M715.2,306c0,88.1-35.7,167.9-93.5,225.7c-28.9,28.9-63.4,52.3-101.6,68.4c-19.1,8.1-39.1,14.3-60.1,18.6V613 H332v5.7c-21-4.3-41-10.5-60.1-18.6c-38.2-16.2-72.7-39.5-101.5-68.4C112.6,473.9,76.9,394.1,76.9,306s35.7-167.9,93.5-225.7 c28.9-28.9,63.4-52.3,101.6-68.4C291,3.8,311-2.4,332-6.7V-1h128v-5.7c21,4.3,41,10.5,60.1,18.6c38.2,16.2,72.7,39.5,101.5,68.4 C679.4,138.1,715.2,217.9,715.2,306z"/> <circle class="st1" cx="396" cy="306" r="312.2"/> <circle class="st1" cx="396" cy="306" r="305.3"/> <circle class="st1" cx="396" cy="306" r="298.4"/> <circle class="st2" cx="396" cy="306" r="291.4"/> <circle class="st3" cx="396" cy="306" r="284.5"/> <circle class="st4" cx="396" cy="306" r="277.5"/> <circle class="st4" cx="396" cy="306" r="270.6"/> <circle class="st5" cx="396" cy="306" r="263.7"/> <circle class="st5" cx="396" cy="306" r="256.7"/> <circle class="st6" cx="396" cy="306" r="249.8"/> <circle class="st7" cx="396" cy="306" r="242.9"/> <circle class="st8" cx="396" cy="306" r="235.9"/> <circle class="st9" cx="396" cy="306" r="229"/> <circle class="st10" cx="396" cy="306" r="222"/> <circle class="st10" cx="396" cy="306" r="215.1"/> <circle class="st11" cx="396" cy="306" r="208.2"/> <circle class="st12" cx="396" cy="306" r="201.2"/> <circle class="st13" cx="396" cy="306" r="194.3"/> <circle class="st14" cx="396" cy="306" r="187.3"/> <circle class="st15" cx="396" cy="306" r="180.4"/> <circle class="st16" cx="396" cy="306" r="173.5"/> <circle class="st17" cx="396" cy="306" r="166.5"/> <circle class="st18" cx="396" cy="306" r="159.6"/> <circle class="st19" cx="396" cy="306" r="152.7"/> <circle class="st20" cx="396" cy="306" r="145.7"/> <circle class="st21" cx="396" cy="306" r="138.8"/> <circle class="st22" cx="396" cy="306" r="131.8"/> <circle class="st23" cx="396" cy="306" r="124.9"/> <circle class="st24" cx="396" cy="306" r="118"/> <circle class="st25" cx="396" cy="306" r="111"/> <circle class="st26" cx="396" cy="306" r="104.1"/> <circle class="st27" cx="396" cy="306" r="97.1"/> <circle class="st28" cx="396" cy="306" r="90.2"/> <circle class="st29" cx="396" cy="306" r="83.3"/> <circle class="st30" cx="396" cy="306" r="76.3"/> <circle class="st31" cx="396" cy="306" r="69.4"/> <circle class="st32" cx="396" cy="306" r="62.4"/> <circle class="st33" cx="396" cy="306" r="55.5"/> <circle class="st34" cx="396" cy="306" r="48.6"/> <circle class="st35" cx="396" cy="306" r="41.6"/> <circle class="st36" cx="396" cy="306" r="34.7"/> <circle class="st37" cx="396" cy="306" r="27.8"/> <circle class="st38" cx="396" cy="306" r="20.8"/> <circle class="st39" cx="396" cy="306" r="13.9"/> <circle class="st40" cx="396" cy="306" r="6.9"/> <animateTransform attributeType="xml" attributeName="transform" type="rotate" from="0 160 450" to="360 160 450" dur="4s" repeatCount="indefinite"/> </g> </g> <rect x="66" y="63.4" class="st41" width="660" height="207.8"/> <text transform="matrix(1 0 0 1 274.5025 84.6501)"><tspan x="0" y="0" class="st42 st43">Proof of Concept of awesomess</tspan><tspan x="-173.9" y="108" class="st42 st44">AWESOMENESS</tspan></text> <text transform="matrix(1 0 0 1 96.9248 248.0947)" class="st42 st45">This SVG is proves that you, #{ user.username }, did something truly fantastical</text> <g> <path class="st46" d="M273.6,483.1l-27.9-35.5l15-42.6l-43.4-12.3l-12.9-43.2l-42.4,15.6l-35.9-27.4L101,375.2l-45.1-1.1l1.7,45.1 l-37.1,25.6l27.9,35.5l-15,42.6l43.4,12.3l12.9,43.2l42.4-15.6l35.9,27.4l25.1-37.5l45.1,1.1l-1.7-45.1L273.6,483.1z M82.1,494.6 l-2-2.6l-7.8,2.6l-0.1,3.3l-7,2.3l1.9-23.7l7-2.3l15.3,17.9L82.1,494.6z M106.8,486.4l-7-11.4l1.2,13.4l-7.1,2.4l-13.6-18.5 l7.3-2.4l7.7,12.6l-1.5-14.6l6.7-2.2l7.7,12.6l-1.5-14.6l7-2.3l0.1,23L106.8,486.4z M121.9,481.4l-6.9-20.8l17.6-5.8l1.7,5.2 l-10.7,3.6l0.8,2.5l9.7-3.2l1.7,5.2l-9.7,3.2l0.9,2.6l11-3.6l1.7,5.2L121.9,481.4z M151.6,471.7c-3.6,1.2-8,1.3-11.5,0.1l0.8-6 c1.9,0.8,4.1,1,6.2,1c1,0,4.7-0.2,4.1-2c-0.5-1.6-4.1-0.7-5.2-0.6c-2.6,0.2-5.6,0.1-7.3-2.2c-2.1-2.8-1.4-6.6,1.1-8.9 c3.6-3.3,9.8-4.3,14.5-3.1l-0.8,6c-1.2-0.2-9.4-1.3-9,1.1c0.3,1.4,2.9,0.9,3.9,0.8c2.1-0.1,4.4-0.3,6.4,0.5c2.5,1,3.8,3.7,3.7,6.3 C158.2,468.4,154.7,470.7,151.6,471.7C148,472.9,156.3,470.2,151.6,471.7z M172.5,464.9c-4.6,1.5-9.9,0.6-13-3.3 c-3-3.7-3.4-9.2-0.7-13.1c2.8-4.1,8.3-6.2,13.1-5.4c4.8,0.8,8.3,4.7,9,9.5C181.6,458.2,177.7,463.1,172.5,464.9z M203.3,454.3 l-3.8-11.4l-0.4,10.5l-4.5,1.5l-6.7-8.2l3.8,11.4l-6,2l-6.9-20.8l7.3-2.4l8.1,9.3l0.9-12.3l7.3-2.4l6.9,20.8L203.3,454.3z M212.2,451.3l-6.9-20.8l17.6-5.8l1.7,5.2l-10.7,3.6l0.8,2.5l9.7-3.2l1.7,5.2l-9.7,3.2l0.9,2.6l11-3.6l1.7,5.2L212.2,451.3z"/> <path class="st46" d="M167.4,449.3c-5.8,1.9-2.6,11.6,3.2,9.9C176.3,457.4,173.1,447.4,167.4,449.3 C165,450.1,169.8,448.5,167.4,449.3z"/> <polygon class="st46" points="76.7,487.7 72.6,482.3 72.4,489.1 "/> </g> </svg>'>
}
  end
end