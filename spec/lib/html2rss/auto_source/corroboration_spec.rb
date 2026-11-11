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
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
