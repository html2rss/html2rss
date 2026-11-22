# frozen_string_literal: true

# rubocop:disable RSpec/MultipleMemoizedHelpers -- page-links double + article factory per verdict path

RSpec.describe Html2rss::AutoSource::Corroboration do
  subject(:corroboration) do
    described_class.new do
      builds << true
      page_links
    end
  end

  let(:builds) { [] }
  let(:sparse) { false }
  let(:placements) { {} }
  let(:page_links) { instance_double(Html2rss::AutoSource::PageLinks, sparse?: sparse) }
  let(:scraper) { Html2rss::AutoSource::Scraper::JsonState }
  let(:build_article) do
    lambda do |path, **fields|
      Html2rss::Article.new(url: "https://example.com#{path}", title: 'Some article title', id: path, scraper:,
                            **fields)
    end
  end
  let(:article) { build_article['/news/2026/10/harbor-ferry-route-returns'] }
  let(:verdict) { corroboration.verdict(article, cohort: [article]) }

  before do
    allow(page_links).to receive(:placement) { |url| placements.fetch(url.path, :absent) }
    allow(page_links).to receive(:identity, &:article_identity)
  end

  describe '#verdict' do
    context 'with an exempt scraper' do
      let(:scraper) { Html2rss::AutoSource::Scraper::NativeFeed }

      it 'keeps the item without building page links', :aggregate_failures do
        expect(verdict).to eq(:keep)
        expect(builds).to be_empty
      end
    end

    context 'without a scraper' do
      let(:scraper) { nil }

      it 'keeps the item' do
        expect(verdict).to eq(:keep)
      end
    end

    it 'checks every corroborated scraper', :aggregate_failures do
      Html2rss::AutoSource::Scraper::CORROBORATED_SCRAPERS.each do |checked|
        item = Html2rss::Article.new(url: 'https://example.com/x', title: 'T', id: 'x', scraper: checked)

        expect(corroboration.verdict(item, cohort: [item])).to eq(:not_on_page)
      end
    end

    it 'builds page links once across verdicts' do
      2.times { corroboration.verdict(article, cohort: [article]) }

      expect(builds.size).to eq(1)
    end

    describe '#canonical_url' do
      let(:canonical) { Html2rss::Url.from_absolute('https://example.com/news/canonical') }

      before { allow(page_links).to receive(:canonical_url).with(article.url).and_return(canonical) }

      it 'returns the page anchor URL for a checked item' do
        expect(corroboration.canonical_url(article)).to eq(canonical)
      end

      it 'returns nil when the item already carries that URL' do
        allow(page_links).to receive(:canonical_url).with(article.url).and_return(article.url)

        expect(corroboration.canonical_url(article)).to be_nil
      end

      it 'returns nil for an exempt scraper' do
        exempt = build_article['/news/x', scraper: Html2rss::AutoSource::Scraper::SemanticHtml]

        expect(corroboration.canonical_url(exempt)).to be_nil
      end
    end

    it 'keeps a content placement' do
      placements[article.url.path] = :content

      expect(verdict).to eq(:keep)
    end

    it 'drops a chrome-only placement as :chrome_only' do
      placements[article.url.path] = :chrome

      expect(verdict).to eq(:chrome_only)
    end

    it 'drops an unrendered URL as :not_on_page even when it scores well' do
      dated = build_article['/news/2026/10/a-b-c', description: 'Desc', published_at: '2026-10-20T08:00:00Z']

      expect(corroboration.verdict(dated, cohort: [dated])).to eq(:not_on_page)
    end

    context 'with a cohort the page mostly does not render' do
      let(:cohort) { %w[a-b-c d-e-f g-h-i j-k-l].map { build_article["/news/2026/10/#{_1}"] } }
      let(:absent_member) { cohort.last }

      it 'drops an absent member as :not_on_page when half the cohort is content' do
        cohort.first(2).each { placements[_1.url.path] = :content }

        expect(corroboration.verdict(absent_member, cohort:)).to eq(:not_on_page)
      end

      it 'drops an absent member as :not_on_page when most of the cohort is content' do
        cohort.first(3).each { placements[_1.url.path] = :content }

        expect(corroboration.verdict(absent_member, cohort:)).to eq(:not_on_page)
      end

      it 'scores an absent member when less than half the cohort is content', :aggregate_failures do
        trio = cohort.first(3)
        placements[cohort.first.url.path] = :content

        expect(corroboration.verdict(absent_member, cohort:)).to eq(:unlikely)
        expect(corroboration.verdict(trio.last, cohort: trio)).to eq(:unlikely)
      end

      it 'needs MIN_COHORT_SIZE items before the share counts', :aggregate_failures do
        pair = %w[a-b-c d-e-f].map { build_article["/news/2026/10/#{_1}", description: 'D', published_at: '2026'] }
        trio = %w[a-b-c d-e-f g-h-i].map { build_article["/news/2026/10/#{_1}", description: 'D'] }

        expect(corroboration.verdict(pair.first, cohort: pair)).to eq(:not_on_page)
        expect(corroboration.verdict(trio.first, cohort: trio)).to eq(:keep)
      end

      it 'counts absence one against the score', :aggregate_failures do
        bare = cohort.first
        described = build_article[bare.url.path, description: 'D']

        expect(corroboration.verdict(bare, cohort:)).to eq(:unlikely)
        expect(corroboration.verdict(described, cohort:)).to eq(:keep)
      end

      it 'drops a dated, cohesive cohort that would otherwise reach the threshold' do
        comments = %w[jane-marlow-ortiz omar-lindqvist-hale rita-osei-brandt].map do |slug|
          build_article["/people/#{slug}", published_at: '2026-10-20']
        end

        expect(comments.map { corroboration.verdict(_1, cohort: comments) }).to all(eq(:unlikely))
      end

      it 'still drops a chrome-only member as :chrome_only' do
        placements[absent_member.url.path] = :chrome

        expect(corroboration.verdict(absent_member, cohort:)).to eq(:chrome_only)
      end

      it 'computes the content share once per cohort' do
        allow(cohort).to receive(:count).and_call_original
        cohort.each { corroboration.verdict(_1, cohort:) }

        expect(cohort).to have_received(:count).once
      end
    end

    context 'with a peripheral placement' do
      before { placements['/news/2026/10/harbor-ferry-route-returns'] = :peripheral }

      it 'keeps an article-shaped dated item' do
        dated = build_article['/news/2026/10/harbor-ferry-route-returns', published_at: '2026-10-20T08:00:00Z']

        expect(corroboration.verdict(dated, cohort: [dated])).to eq(:keep)
      end

      it 'keeps an item scoring above the threshold' do
        rich = build_article['/news/2026/10/harbor-ferry-route-returns', published_at: '2026-10-20', description: 'D',
                                                                         image: 'https://example.com/i.png']

        expect(corroboration.verdict(rich, cohort: [rich])).to eq(:keep)
      end

      it 'drops a bare item as :unlikely' do
        expect(verdict).to eq(:unlikely)
      end
    end

    context 'with a sparse page' do
      let(:sparse) { true }

      it 'keeps a content placement' do
        placements[article.url.path] = :content

        expect(verdict).to eq(:keep)
      end

      it 'scores a chrome placement instead of dropping it as :chrome_only' do
        placements[article.url.path] = :chrome

        expect(verdict).to eq(:unlikely)
      end

      it 'keeps an unrendered item with two article signals' do
        item = build_article['/app/id1234567890', description: 'Desc', image: 'https://example.com/i.png']

        expect(corroboration.verdict(item, cohort: [item])).to eq(:keep)
      end

      it 'counts the published date, image, and description each once', :aggregate_failures do
        singles = [{ published_at: '2026-10-20' }, { image: 'https://example.com/i.png' }, { description: 'D' }]

        expect(singles.map { corroboration.verdict(build_article['/a/b', **_1], cohort: []) }).to all(eq(:unlikely))
        both = build_article['/a/b', description: 'Desc', published_at: '2026-10-20']
        expect(corroboration.verdict(both, cohort: [])).to eq(:keep)
      end

      it 'adds one for an article-shaped path (content segment or post slug)', :aggregate_failures do
        expect(corroboration.verdict(build_article['/news/x', description: 'D'], cohort: [])).to eq(:keep)
        expect(corroboration.verdict(build_article['/press/some-long-slug', description: 'D'], cohort: []))
          .to eq(:keep)
        expect(corroboration.verdict(build_article['/2026/10/some-long-slug', description: 'D'], cohort: []))
          .to eq(:keep)
      end

      it 'subtracts one for a section-root path', :aggregate_failures do
        item = build_article['/traffic/', description: 'Desc', image: 'https://example.com/i.png']
        dated = build_article['/traffic/', description: 'Desc', image: 'https://example.com/i.png',
                                           published_at: '2026-10-20']

        expect(corroboration.verdict(item, cohort: [])).to eq(:unlikely)
        expect(corroboration.verdict(dated, cohort: [])).to eq(:keep)
      end

      it 'scores a root-level post slug zero', :aggregate_failures do
        dated = build_article['/harbor-ferry-route-returns', published_at: '2026-10-20']
        described = build_article['/harbor-ferry-route-returns', description: 'D', published_at: '2026-10-20']

        expect(corroboration.verdict(dated, cohort: [])).to eq(:unlikely)
        expect(corroboration.verdict(described, cohort: [])).to eq(:keep)
      end

      it 'subtracts one for a shallow path without a post slug', :aggregate_failures do
        short = build_article['/about-us', description: 'D', published_at: '2026-10-20']
        root = build_article['/', description: 'D', published_at: '2026-10-20']

        expect(corroboration.verdict(short, cohort: [])).to eq(:unlikely)
        expect(corroboration.verdict(root, cohort: [])).to eq(:unlikely)
      end

      it 'keeps a thin dated cohort under root-level slugs without counting absence' do
        thin = %w[harbor-ferry-route-returns library-extends-weekend-hours river-cleanup-volunteers-record]
               .map { build_article["/#{_1}", published_at: '2026-10-20'] }

        expect(thin.map { corroboration.verdict(_1, cohort: thin) }).to all(eq(:keep))
      end

      it 'adds one for a cohesive cohort of at least MIN_COHORT_SIZE items' do
        cohort = %w[a b c].map { build_article["/people/#{_1}", description: 'D'] }

        expect(corroboration.verdict(cohort.first, cohort:)).to eq(:keep)
      end

      it 'computes cohort cohesion once per cohort' do
        cohort = %w[a b c].map { build_article["/people/#{_1}", description: 'D'] }
        allow(cohort).to receive(:map).and_call_original
        cohort.each { corroboration.verdict(_1, cohort:) }

        expect(cohort).to have_received(:map).once
      end

      it 'needs MIN_COHORT_SIZE items for cohesion' do
        cohort = %w[a b].map { build_article["/people/#{_1}", description: 'D'] }

        expect(corroboration.verdict(cohort.first, cohort:)).to eq(:unlikely)
      end

      it 'needs at least half the cohort under one parent path', :aggregate_failures do
        half = %w[/y/c /x/a /x/b /z/d].map { build_article[_1, description: 'D'] }
        minority = %w[/x/a /y/b /z/c].map { build_article[_1, description: 'D'] }

        expect(corroboration.verdict(half.first, cohort: half)).to eq(:keep)
        expect(corroboration.verdict(minority.first, cohort: minority)).to eq(:unlikely)
      end

      it 'drops a JSON icon menu of section roots as :unlikely' do
        menu = %w[traffic weather lottery podcasts].map do |slug|
          build_article["/#{slug}/", image: "https://example.com/icons/#{slug}.svg"]
        end

        expect(menu.map { corroboration.verdict(_1, cohort: menu) }).to all(eq(:unlikely))
      end
    end
  end

  describe '#page_order' do
    before do
      allow(page_links).to receive(:content_position) { |url| %w[/a /b /c /d /e /f].each_with_index.to_h[url.path] }
    end

    it 'orders items by content position, unplaced items last in their given order' do
      items = %w[/x /c /a /y /f /b /e /d /z].map { build_article[_1] }

      expect(corroboration.page_order(items).map { _1.url.path }).to eq(%w[/a /b /c /d /e /f /x /y /z])
    end

    it 'puts media items first, then the other items, each in document order' do
      items = [build_article['/a'], build_article['/f', media: true], build_article['/y', media: true],
               build_article['/c'], build_article['/e', media: true], build_article['/b']]

      expect(corroboration.page_order(items).map { _1.url.path }).to eq(%w[/e /f /y /a /b /c])
    end
  end

  describe '#media_page?' do
    let(:media) { Array.new(3) { |index| build_article["/podcasts/episode-#{index}", media: true] } }
    let(:stories) { Array.new(2) { |index| build_article["/news/story-#{index}"] } }

    before { (media + stories).each { placements[_1.url.path] = :content } }

    it 'is a media page when more than half of the shown page items are media' do
      expect(corroboration.media_page?(media + stories)).to be(true)
    end

    it 'is no media page when media items are half of the shown page items or fewer', :aggregate_failures do
      expect(corroboration.media_page?(media.first(2) + stories)).to be(false)
      expect(corroboration.media_page?([])).to be(false)
    end

    it 'counts a structured media item and the card rendering it once' do
      cards = media.map { build_article[_1.url.path, scraper: Html2rss::AutoSource::Scraper::SemanticHtml] }

      expect(corroboration.media_page?(media + cards + stories)).to be(true)
    end

    it 'counts items the page keys as one article once, whatever their placement param', :aggregate_failures do
      allow(page_links).to receive(:identity, &:path)
      placed = media.map { build_article["#{_1.url.path}?pos=latest", scraper: Html2rss::AutoSource::Scraper::SemanticHtml] }
      placed.each { placements[_1.url.path] = :content }

      expect(corroboration.media_page?(media + placed + stories)).to be(true)
      expect(page_links).to have_received(:identity).at_least(:once)
    end

    it 'leaves out media items the page does not show in its content' do
      media.each { placements[_1.url.path] = :peripheral }

      expect(corroboration.media_page?(media + stories)).to be(false)
    end

    it 'leaves out items not read off the page' do
      feed = Array.new(3) do |index|
        Html2rss::Article.new(url: "https://example.com/feed-#{index}", title: 'Feed story', id: "f#{index}",
                              scraper: Html2rss::AutoSource::Scraper::NativeFeed)
      end

      expect(corroboration.media_page?(media.first(2) + feed)).to be(true)
    end
  end

  describe '#shown?' do
    it 'shows a checked item rendered as a content anchor' do
      placements[article.url.path] = :content

      expect(corroboration.shown?(article)).to be(true)
    end

    it 'does not show a checked item rendered only outside the content', :aggregate_failures do
      %i[chrome peripheral absent].each do |placement|
        placements[article.url.path] = placement

        expect(corroboration.shown?(article)).to be(false)
      end
    end

    it 'takes an exempt item as shown without building page links', :aggregate_failures do
      feed_item = Html2rss::Article.new(url: 'https://example.com/x', title: 'T', id: 'x',
                                        scraper: Html2rss::AutoSource::Scraper::NativeFeed)

      expect(corroboration.shown?(feed_item)).to be(true)
      expect(builds).to be_empty
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
