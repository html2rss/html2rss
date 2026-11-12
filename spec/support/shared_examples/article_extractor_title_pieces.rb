# frozen_string_literal: true

# Host specs define title_for as a lambda: ->(html) { String or nil }, html being one <article> card.
# Both extractors read kicker and headline through Html::TitlePieces (one rule; see its class notes):
# headline piece, kicker, concealed, date, lead and tag pieces are all judged by element, so these must agree.
RSpec.shared_examples 'article extractor title pieces' do
  {
    'a field-label kicker child' => [
      '<span class="kicker"><span>Thema:</span> Verkehr</span><h2><a href="/news/story">Tram line extends</a></h2>',
      'Verkehr: Tram line extends'
    ],
    'a kicker child ending in a colon' => [
      '<span class="kicker"><strong>Conflict:</strong></span><h2><a href="/news/story">Headline</a></h2>',
      'Conflict: Headline'
    ],
    'field-label kicker children in de, fr and es' => [
      '<span class="kicker"><span>Thème :</span><span>Tema:</span> Port</span>' \
      '<h2><a href="/news/story">Tax vote</a></h2>',
      'Port: Tax vote'
    ],
    'clock, time and type-marker kicker children' => [
      '<span class="kicker"><span>09:05</span><time>Oct 20</time><span>Video</span><span>Harbor</span></span>' \
      '<h2><a href="/news/story">Ferry route returns</a></h2>',
      'Harbor: Ferry route returns'
    ],
    'a time element in the headline anchor' => [
      '<h2><a href="/news/story"><span><time>19:47</time></span><span>Tram line extends</span></a></h2>',
      'Tram line extends'
    ],
    'a clock-only element in the headline' => [
      '<h2><a href="/news/story"><span class="stamp">19:47 Uhr</span> Tram line extends</a></h2>',
      'Tram line extends'
    ],
    'a clock run into the headline text' => [
      '<h2><a href="/news/story">10:00 Budget vote passes</a></h2>',
      '10:00 Budget vote passes'
    ],
    'a leading score' => [
      '<h2><a href="/news/story">28:25 – Derby ends level</a></h2>',
      '28:25 – Derby ends level'
    ],
    'a clock and label opening the headline text' => [
      '<h2><a href="/news/story">20:15 Uhr: Neuer Krimi am Abend</a></h2>',
      '20:15 Uhr: Neuer Krimi am Abend'
    ],
    'a screen-reader label element in the headline' => [
      '<h2><a href="/news/story"><span class="sr-only">Article type: Video</span> Tram line extends</a></h2>',
      'Tram line extends'
    ],
    'a kicker group wrapping kicker and title' => [
      '<h2><a href="/news/story"><span class="kicker-group"><span class="kicker">Transit</span> ' \
      '<span class="title">Tram line extends</span></span></a></h2>',
      'Transit: Tram line extends'
    ],
    'a has-kicker modifier wrapping the kicker and headline text' => [
      '<h2><a href="/news/story"><span class="headline__inner headline__inner--has-kicker">' \
      '<span class="kicker">Transit</span> Tram line extends</span></a></h2>',
      'Transit: Tram line extends'
    ],
    'a has-kicker modifier holding only the headline text' => [
      '<h2><a href="/news/story"><span class="headline--has-kicker">20:15 | Krimi am Abend</span></a></h2>',
      '20:15 | Krimi am Abend'
    ],
    'a separator after a kicker in the heading' => [
      '<h2><a href="/news/story"><span class="kicker">Transit</span> / Tram line extends</a></h2>',
      'Transit: Tram line extends'
    ],
    'a kicker-marked row holding the kicker and a status' => [
      '<div class="eyebrow-row"><span class="eyebrow">Transit</span> <span>Updated</span></div>' \
      '<h2><a href="/news/story">Tram line extends</a></h2>',
      'Transit: Tram line extends'
    ],
    'a kicker-marked heading' => [
      '<h2 class="headline--with-kicker"><a href="/news/story">20:15 | Krimi am Abend</a></h2>',
      '20:15 | Krimi am Abend'
    ],
    'a has-kicker modifier holding the heading text beside a read-more link' => [
      '<h2><span class="headline--has-kicker">20:15 | Krimi am Abend</span></h2><a href="/news/story">Read more</a>',
      '20:15 | Krimi am Abend'
    ],
    'a kicker beside an image-only heading' => [
      '<span class="kicker">Weather</span><h2><a href="/news/story"><img src="/a.jpg" alt=""></a></h2>',
      'Weather'
    ],
    'a dated time element in the headline' => [
      '<h2><a href="/news/story"><time datetime="2026-10-20">Oct 20</time> Tram line extends</a></h2>',
      'Tram line extends'
    ],
    'an icon leaf in the kicker' => [
      '<span class="kicker"><span class="kicker__icon" aria-hidden="true"></span>Transit</span>' \
      '<h2><a href="/news/story">Tram line extends</a></h2>',
      'Transit: Tram line extends'
    ],
    'a time leaf beside the kicker topic' => [
      '<span class="eyebrow"><time class="eyebrow__time">10:30</time> <b class="eyebrow__topic">Transit</b></span>' \
      '<h2><a href="/news/story">Tram line extends</a></h2>',
      'Transit: Tram line extends'
    ],
    'a kicker-marked clock leaf before the kicker' => [
      '<span class="kicker__time">10:30</span><span class="kicker">Transit</span>' \
      '<h2><a href="/news/story">Tram line extends</a></h2>',
      'Transit: Tram line extends'
    ],
    'a kicker made of a topic, a sub part and a time' => [
      '<div class="kicker"><time>10:30</time> <b class="kicker__topic">Transit</b> ' \
      '<b class="kicker__sub">East</b></div>' \
      '<h2><a href="/news/story">Tram line extends</a></h2>',
      'Transit East: Tram line extends'
    ],
    'a clock element in the middle of the headline' => [
      '<h2><a href="/news/story">Night train leaves at <strong>20:15</strong> from platform four</a></h2>',
      'Night train leaves at 20:15 from platform four'
    ],
    'a time element ending the headline' => [
      '<h2><a href="/news/story">Budget vote passes late <time>22:10</time></a></h2>',
      'Budget vote passes late'
    ],
    'a time element inside running headline text' => [
      '<h2><a href="/news/story">Council moved to <time datetime="2026-11-14">Friday</time> after the row</a></h2>',
      'Council moved to Friday after the row'
    ],
    'date, duration and time-cell elements around the headline' => [
      '<h2><a href="/news/story"><span class="p-list__timeCell">3 hours ago</span><span>Tram line extends</span>' \
      '<div class="item-duration">0:52</div><span class="newsBlock-date">November 10, 2026</span></a></h2>',
      'Tram line extends'
    ],
    'a Japanese date chip closing the headline without a date class' => [
      '<h2><a href="/news/story"><div><span>市が補修費を支出へ</span></div><span class="stamp">11月12日 16:42</span></a></h2>',
      '市が補修費を支出へ'
    ],
    'two Japanese date chips closing the headline' => [
      '<h2><a href="/news/story"><span>市が補修費を支出へ</span><span>11月12日</span><span>11月13日 9:05</span></a></h2>',
      '市が補修費を支出へ'
    ],
    'a Japanese date chip before a dated element closing the headline' => [
      '<h2><a href="/news/story"><span>市が補修費を支出へ</span><span>11月12日</span><span class="date">11月13日</span></a></h2>',
      '市が補修費を支出へ'
    ],
    'a Japanese date chip opening the headline without a date class' => [
      '<h2><a href="/news/story"><span class="stamp">11月12日</span><span>市が補修費を支出へ</span></a></h2>',
      '市が補修費を支出へ'
    ],
    'a Japanese date inside the headline text' => [
      '<h2><a href="/news/story"><span>政府は</span> <span>11月12日</span> <span>に支出へ</span></a></h2>',
      '政府は 11月12日 に支出へ'
    ],
    'an update or candidate class that only contains a date word' => [
      '<h2><a href="/news/story"><span class="update-note">Tram</span> <span class="candidates">line</span></a></h2>',
      'Tram line'
    ],
    'an in-heading topline and headline pair' => [
      '<h3><span class="teaser__topline">Transit</span><span class="teaser__headline">Tram line extends</span></h3>' \
      '<a href="/news/story">More</a>',
      'Transit: Tram line extends'
    ],
    'an unmarked kicker block before a headline-marked span' => [
      '<a href="/news/story"><h3 class="card-headline"><div style="color:var(--card-kicker-text)">Transit</div>' \
      '<span class="headline-text">Tram line extends</span></h3></a>',
      'Transit: Tram line extends'
    ],
    'a prefix label opening the heading text' => [
      '<h1 class="TeaserHeadline__root"><span class="TeaserHeadline__prefix">Explainer</span>Tram line extends</h1>' \
      '<a href="/news/story">More</a>',
      'Explainer: Tram line extends'
    ],
    'a label leaf after a dropped date opening the anchor' => [
      '<a href="/news/story"><div class="list__heading"><time datetime="2026-11-12">12 Nov</time> ' \
      '<span class="label">Daily brief</span></div><p class="list__description">Tram line extends</p></a>',
      'Daily brief: Tram line extends'
    ],
    'a heading kicker that already opens the headline' => [
      '<h3><span class="kicker">Harbor</span><span class="title">Harbor ferry returns</span></h3>' \
      '<a href="/news/story">More</a>',
      'Harbor ferry returns'
    ],
    'trailing tag and subtitle pieces after the headline' => [
      '<h3><a href="/news/story">Tram line extends <span class="gsc-tag">Transport</span></a></h3>' \
      '<h3><span class="subTitle">East side</span></h3>',
      'Tram line extends'
    ],
    'an anchor card with a title span, a lead paragraph and a tag footer' => [
      '<a href="/news/story"><div class="item__header"><span class="item__title">Tram line extends</span>' \
      '<time>18:20</time></div><div><p>The council approved the eastern route.</p></div>' \
      '<footer><span class="gsc-tag">Transport</span></footer></a>',
      'Tram line extends'
    ],
    'an anchor card with a title, a lead and no heading' => [
      '<a href="/news/story" class="teaser"><span class="teaser__title">Tram line extends</span>' \
      '<p class="teaser__lead">The council approved the eastern route.</p></a>',
      'Tram line extends'
    ],
    'an anchor with a lead paragraph and plain title text' => [
      '<a href="/news/story"><span>Tram line extends</span><p class="teaser-lead">The council approved it.</p></a>',
      'Tram line extends'
    ],
    'a data-title attribute on the anchor' => [
      '<a href="/news/story" data-title="Tram line extends"><span>Transit</span> Tram line extends ' \
      '<span>The council approved the eastern route.</span></a>',
      'Tram line extends'
    ],
    'a kicker-marked block before a titled span in the anchor' => [
      '<a href="/news/story"><div class="teaser__kicker"><span>Morning show</span></div>' \
      '<span class="teaser__title">Tram line extends</span></a>',
      'Morning show: Tram line extends'
    ],
    'a meta container with a separator dot and a time before the title' => [
      '<a href="/news/story"><span class="meta"><time>Just in</time><span class="dot">•</span>Regional</span>' \
      '<span class="item__title">Tram line extends</span></a>',
      'Regional: Tram line extends'
    ],
    'a category leaf before the anchor inside the heading' => [
      '<h3 class="news__title"><div class="news__date">November 10, 2026</div><div class="news__cat">Article</div>' \
      '<a href="/news/story">Tram line extends</a></h3>',
      'Article: Tram line extends'
    ],
    'a badge and a topic in one box before the title' => [
      '<h2><span class="box"><span class="premium">Plus</span><span class="box__head">Transit</span></span> ' \
      '<span class="title"><a href="/news/story">Tram line extends</a></span></h2>',
      'Transit: Tram line extends'
    ],
    'a type badge above the heading and a topline inside it' => [
      '<a href="/news/story"><p class="teaser__topline-box"><span class="label">Interview</span></p>' \
      '<h3><span class="teaser__topline">Transit</span> ' \
      '<span class="teaser__headline">Tram line extends</span></h3></a>',
      'Transit: Tram line extends'
    ],
    'a heading split over several links to the story' => [
      '<h2><a href="/news/story">Where to ski this year? </a><br><a href="/news/story">The resorts that won</a></h2>',
      'Where to ski this year? The resorts that won'
    ],
    'a picture caption before the titled span' => [
      '<a href="/news/story"><figure><img src="/a.jpg" alt=""><figcaption>Photo desk</figcaption></figure>' \
      '<span class="card__title">Tram line extends</span></a>',
      'Tram line extends'
    ],
    'screen-reader-only and off-screen text in the headline' => [
      '<h2><a href="/news/story"><span class="sr-only">video 1 minute 33</span> Tram line extends ' \
      '<span class="h-offscreen">(opens a submenu)</span>' \
      '<span class="_screen-reader-only">Duration 9 min</span></a></h2>',
      'Tram line extends'
    ],
    'a link whose only text is screen-reader-only' => [
      '<h2><a href="/news/story"><span class="sr-only">Tram line extends</span></a></h2>',
      'Tram line extends'
    ],
    'a visually hidden colon between a label and the headline' => [
      '<h3><div class="label"><span class="label-text">Transit</span><span class="visually-hidden">: </span></div>' \
      '<div class="headline">Tram line extends</div></h3><a href="/news/story">More</a>',
      'Transit: Tram line extends'
    ],
    'a label element in the middle of the headline' => [
      '<h2><a href="/news/story">Why the <em>Category:</em> field confuses editors</a></h2>',
      'Why the Category: field confuses editors'
    ],
    'a classed badge before the kicker' => [
      '<span class="badge">Plus</span><span class="kicker">Transit</span>' \
      '<h2><a href="/news/story">Tram line extends</a></h2>',
      'Transit: Tram line extends'
    ],
    'two sibling kickers in a plain wrapper' => [
      '<div class="meta"><span class="kicker">Transit</span> <span class="kicker">East</span></div>' \
      '<h2><a href="/news/story">Tram line extends</a></h2>',
      'Transit: Tram line extends'
    ],
    'an empty time element opening the headline' => [
      '<h2><a href="/news/story"><time datetime="2026-10-20"></time>Tram line extends</a></h2>',
      'Tram line extends'
    ],
    'a headline made only of noise elements' => [
      '<span class="kicker">Weather</span><h2><a href="/news/story"><span><time>19:47</time></span></a></h2>',
      'Weather'
    ],
    'an indented headline opening with a time element' => [
      "<h2>\n  <a href=\"/news/story\">\n    <time>19:47</time>\n    Tram line extends\n  </a>\n</h2>",
      'Tram line extends'
    ],
    'a kicker ending in a separator' => [
      '<span class="kicker">Transit &gt;</span><h2><a href="/news/story">Tram line extends</a></h2>',
      'Transit: Tram line extends'
    ],
    'a camelCase title class' => [
      '<a href="/news/story"><span>Transit</span><span class="teaserTitle">Tram line extends</span></a>',
      'Transit: Tram line extends'
    ],
    'a two-word label class' => [
      '<h2><a href="/news/story"><span class="region-name">Coast</span> Tram line extends</a></h2>',
      'Coast: Tram line extends'
    ],
    'a tag piece opening the headline' => [
      '<h2><a href="/news/story"><span class="tag">Politics</span> Council reaches a deal</a></h2>',
      'Politics Council reaches a deal'
    ],
    'a tag piece closing the headline before a time' => [
      '<h2>' \
      '<a href="/news/story">Council reaches a deal <span class="tag">Politics</span> <time>08:10</time></a></h2>',
      'Council reaches a deal'
    ],
    'a tag piece that is the whole headline' => [
      '<h2><a href="/news/story"><span class="tag">Council reaches a deal</span></a></h2>',
      'Council reaches a deal'
    ],
    'a lead piece that is the whole headline' => [
      '<h2><a href="/news/story"><span class="lead">Council reaches a deal</span></a></h2>',
      'Council reaches a deal'
    ],
    'a hidden-attribute and display-none piece' => [
      '<h2><a href="/news/story">Tram line <span hidden>opens a menu</span>' \
      '<span style="display: none">ad</span>extends</a></h2>',
      'Tram line extends'
    ],
    'a sub-title piece before the title piece' => [
      '<a href="/news/story"><span class="sub-title">Second line</span>' \
      '<span class="title">Tram line extends</span></a>',
      'Second line: Tram line extends'
    ],
    'a label-marked title piece before the title piece' => [
      '<a href="/news/story"><span class="title-label">Feature</span>' \
      '<span class="title">Tram line extends</span></a>',
      'Feature: Tram line extends'
    ],
    'a nested headline box holding a kicker' => [
      '<a href="/news/story"><div class="headline"><span class="headline-kicker">Transit</span>' \
      '<span class="headline-text">Tram line extends</span></div><p>Crews start work on Monday.</p></a>',
      'Transit: Tram line extends'
    ],
    'anchor words around a title piece' => [
      '<a href="/news/story">Breaking <span class="title">Tram line extends</span></a>',
      'Breaking Tram line extends'
    ],
    'a concealed kicker-marked piece' => [
      '<span class="kicker sr-only">Article</span><h2><a href="/news/story">Tram line extends</a></h2>',
      'Tram line extends'
    ],
    'a clock-only kicker-marked piece' => [
      '<span class="kicker">19:47</span><h2><a href="/news/story">Tram line extends</a></h2>',
      'Tram line extends'
    ],
    'a date kicker-marked piece' => [
      '<span class="kicker-date">Oct 20</span><h2><a href="/news/story">Tram line extends</a></h2>',
      'Tram line extends'
    ],
    'a label piece after the headline words' => [
      '<h2><a href="/news/story">Tram line extends <span class="label">east</span></a></h2>',
      'Tram line extends east'
    ],
    'a label piece that is the whole headline' => [
      '<h2><a href="/news/story"><span class="label">Tram line extends</span></a></h2>',
      'Tram line extends'
    ],
    'a paragraph before the title piece' => [
      '<a href="/news/story"><p>Crews start work on Monday.</p>' \
      '<span class="title">Tram line extends</span></a>',
      'Tram line extends'
    ],
    'a lead piece before the title piece' => [
      '<a href="/news/story"><span class="teaser-lead">Crews start work</span>' \
      '<span class="title">Tram line extends</span></a>',
      'Tram line extends'
    ],
    'a clock piece before the title piece' => [
      '<a href="/news/story"><span>19:47</span><span class="title">Tram line extends</span></a>',
      'Tram line extends'
    ],
    'a box of a badge and a topic before the title piece' => [
      '<a href="/news/story"><div><span>Plus</span><span>Transit</span></div>' \
      '<span class="title">Tram line extends</span></a>',
      'Transit: Tram line extends'
    ],
    'a worded box before the title piece' => [
      '<a href="/news/story"><div>Transit <b>East</b></div><span class="title">Tram line extends</span></a>',
      'Transit East: Tram line extends'
    ],
    'a box around a paragraph before the title piece' => [
      '<a href="/news/story"><div><p>Crews start work on Monday.</p></div>' \
      '<span class="title">Tram line extends</span></a>',
      'Tram line extends'
    ],
    'two pieces before the title piece' => [
      '<a href="/news/story"><span>Region</span><span>Transit</span>' \
      '<span class="title">Tram line extends</span></a>',
      'Transit: Tram line extends'
    ],
    'words between a piece and the title piece' => [
      '<a href="/news/story"><div>' \
      '<span>Transit</span> by staff <span class="title">Tram line extends</span></div></a>',
      'Tram line extends'
    ],
    'lead words in the box of the title piece' => [
      '<a href="/news/story"><div>Read <span>Transit</span>' \
      '<span class="title">Tram line extends</span></div></a>',
      'Tram line extends'
    ],
    'concealed, time and blank pieces before the title piece' => [
      '<a href="/news/story"><span>Transit</span><span class="sr-only">Article</span>' \
      '<time>08:10</time><span>|</span><span class="title">Tram line extends</span></a>',
      'Transit: Tram line extends'
    ],
    'a piece before the heading of a title piece' => [
      '<span>Sponsored by</span><h2><span class="title">Tram line extends</span>' \
      '<a href="/news/story">More</a></h2>',
      'Tram line extends'
    ],
    'a time after an element in the headline' => [
      '<h2><a href="/news/story">Council <b>meets</b><time>Friday</time> after the vote</a></h2>',
      'Council meets after the vote'
    ],
    'a time before trailing blank text' => [
      '<h2><a href="/news/story">Council meets <time>Friday</time> </a></h2>',
      'Council meets'
    ],
    'an empty tag piece closing the headline' => [
      '<h2><a href="/news/story">Tram line extends<span class="tag"></span></a></h2>',
      'Tram line extends'
    ],
    'an empty label piece opening the headline' => [
      '<h2><a href="/news/story"><span class="label"></span>Tram line extends</a></h2>',
      'Tram line extends'
    ],
    'a concealed label that is the whole headline' => [
      '<h2><a href="/news/story"><span class="label sr-only">Tram line extends</span></a></h2>',
      'Tram line extends'
    ],
    'a live label before a time only' => [
      '<h2><a href="/news/story"><span class="live">Live</span> <time>08:10</time></a></h2>',
      'Live'
    ],
    'a label-marked title piece after the title piece' => [
      '<a href="/news/story"><span class="title">Tram line extends</span>' \
      '<span class="title-label">Feature</span></a>',
      'Tram line extends'
    ],
    'a clock kicker-marked title piece after the title piece' => [
      '<a href="/news/story"><span class="title">Tram line extends</span>' \
      '<span class="kicker-title">19:47</span></a>',
      'Tram line extends'
    ],
    'a clock kicker before a topic kicker' => [
      '<span class="kicker">19:47</span><span class="kicker">Transit</span><h2>' \
      '<a href="/news/story">Tram line extends</a></h2>',
      'Transit: Tram line extends'
    ],
    'a time after blank text in the headline' => [
      '<h2><a href="/news/story">Council <b>meets</b> <time>Friday</time> after the vote</a></h2>',
      'Council meets after the vote'
    ],
    'a time before an element in the headline' => [
      '<h2><a href="/news/story">Council meets <time>Friday</time><b>after</b> the vote</a></h2>',
      'Council meets after the vote'
    ],
    'a piece before the box of the title piece' => [
      '<h2><span>Transit</span><span><span class="title">Tram line extends</span></span></h2>' \
      '<a href="/news/story">More</a>',
      'Transit: Tram line extends'
    ],
    'words after the title piece in its box' => [
      '<a href="/news/story"><div><span>Transit</span>' \
      '<span class="title">Tram line extends</span> by staff</div></a>',
      'Transit: Tram line extends'
    ],
    'a box of a topic and a time before the title piece' => [
      '<a href="/news/story"><div><span>Transit</span><time>08:10</time></div>' \
      '<span class="title">Tram line extends</span></a>',
      'Transit: Tram line extends'
    ],
    'an empty piece between a kicker and the title piece' => [
      '<a href="/news/story"><span>Transit</span><i></i><span class="title">Tram line extends</span></a>',
      'Transit: Tram line extends'
    ],
    'a time after more words in the headline' => [
      '<h2><a href="/news/story">Council <b>meets</b> again <time>Friday</time></a></h2>',
      'Council meets again'
    ],
    'a time and screen-reader text as the only headline words' => [
      '<h2><a href="/news/story"><time>08:10</time><span class="sr-only">Tram line extends</span></a></h2>',
      'Tram line extends'
    ],
    'a time and a lead piece as the only headline words' => [
      '<h2><a href="/news/story"><time>08:10</time><span class="lead">Tram line extends</span></a></h2>',
      'Tram line extends'
    ],
    'a paid label in a marked kicker link beside the title link' => [
      '<div><a href="/news/story"><span class="category overline">Materiał Partnera</span></a>' \
      '<a href="/news/story"><h3>Office space for small firms</h3></a></div>',
      'Office space for small firms'
    ],
    'a paid label opening the link text' => [
      '<h2><a href="/news/story"><span class="label">Sponsored</span> Heat pumps for every budget</a></h2>',
      'Heat pumps for every budget'
    ],
    'a marked paid label before a marked topic' => [
      '<span class="kicker">Sponsored content</span><span class="kicker">Energy</span>' \
      '<h2><a href="/news/story">Heat pumps for every budget</a></h2>',
      'Energy: Heat pumps for every budget'
    ],
    'an ad word as a topic kicker' => [
      '<span class="kicker">Werbung</span><h2><a href="/news/story">New rules for posters</a></h2>',
      'Werbung: New rules for posters'
    ]
  }.each do |shape, (card, title)|
    it "titles a card with #{shape} as #{title.inspect}" do
      expect(title_for.call("<article>#{card}</article>")).to eq(title)
    end
  end
end
