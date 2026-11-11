# frozen_string_literal: true

# Host specs define title_for as a lambda: ->(html) { String or nil }, html being one <article> card.
# Both extractors pick the leaf-most kicker-marked node beside the headline, judge kicker children
# with Article::Title.noise_piece? and drop teaser noise elements (Article::Title.headline_noise_piece?,
# +time+) from the headline, whose text stays verbatim; so these must agree.
RSpec.shared_examples 'article extractor title pieces' do
  {
    'a field-label kicker child' => [
      '<span class="kicker"><span>Thema:</span> Verkehr</span><h2><a href="/news/story">Tram line extends</a></h2>',
      'Verkehr: Tram line extends'
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
    'a kicker ending in a separator' => [
      '<span class="kicker">Transit &gt;</span><h2><a href="/news/story">Tram line extends</a></h2>',
      'Transit: Tram line extends'
    ]
  }.each do |shape, (card, title)|
    it "titles a card with #{shape} as #{title.inspect}" do
      expect(title_for.call("<article>#{card}</article>")).to eq(title)
    end
  end
end
