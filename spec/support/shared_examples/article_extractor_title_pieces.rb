# frozen_string_literal: true

# Host specs define title_for as a lambda: ->(html) { String or nil }, html being one <article> card.
# Both extractors judge kicker children with Article::Title.noise_piece? and drop teaser clock
# elements (Article::Title.clock_piece?, +time+) from the headline, so these must agree.
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
    ]
  }.each do |shape, (card, title)|
    it "titles a card with #{shape} as #{title.inspect}" do
      expect(title_for.call("<article>#{card}</article>")).to eq(title)
    end
  end
end
