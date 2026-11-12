# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength

RSpec.describe Html2rss::AutoSource::Scraper::SemanticHtml do
  describe '.options_key' do
    specify { expect(described_class.options_key).to eq(:semantic_html) }
  end

  describe '.articles?' do
    let(:parsed_body) do
      Nokogiri::HTML.parse <<~HTML
        <html><body><article><a href="/article-1">Article 1</a></article></body></html>
      HTML
    end

    it 'returns true when there are extractable articles' do
      expect(described_class.articles?(parsed_body)).to be true
    end

    it 'returns false when there are no extractable articles' do
      expect(described_class.articles?(nil)).to be false
    end

    it 'returns false for a parsed document without semantic containers' do
      expect(described_class.articles?(Nokogiri::HTML(''))).to be false
    end
  end

  describe '.request_slots' do
    it 'reserves no request slots regardless of options', :aggregate_failures do
      expect(described_class.request_slots).to eq(0)
      expect(described_class.request_slots(max_pages: 3)).to eq(0)
    end
  end

  describe 'with an empty document' do
    let(:parsed_body) { Nokogiri::HTML('') }

    it 'is not extractable and yields no articles', :aggregate_failures do
      expect(described_class.articles?(parsed_body)).to be false
      expect(described_class.new(parsed_body, url: 'https://example.com').to_a).to eq([])
    end
  end

  describe '#initialize' do
    let(:parsed_body) do
      Nokogiri::HTML.parse <<~HTML
        <html><body><article><a href="/article-1">Article 1</a></article></body></html>
      HTML
    end

    it 'is constructible without raising' do
      expect { described_class.new(parsed_body, url: 'https://example.com') }.not_to raise_error
    end

    it 'emits no page-fragment items for containers without a link' do
      anchorless = Nokogiri::HTML.parse <<~HTML
        <html><body><article><h2>No Link Article</h2><p>Description text</p></article></body></html>
      HTML

      expect(described_class.new(anchorless, url: 'https://example.com').to_a).to eq([])
    end

    context 'with a relative story link and a provided document or link resolver' do
      let(:story_html) do
        <<~HTML
          <html><body><article><h2><a href="/news/relative">Relative story</a></h2>
          <p>Useful context paragraph for readers this week.</p></article></body></html>
        HTML
      end
      let(:provided_document) { Html2rss::SST::Normalizer.call(Nokogiri::HTML.parse(story_html)) }

      it 'resolves relative links against the given url' do
        articles = described_class.new(Nokogiri::HTML.parse(story_html), url: 'https://example.net/').to_a

        expect(articles.map { _1.url.to_s }).to eq(['https://example.net/news/relative'])
      end

      it 'uses a provided SST document even without a parsed body' do
        articles = described_class.new(nil, url: 'https://example.com', document: provided_document).to_a

        expect(articles.map { _1.url.to_s }).to eq(['https://example.com/news/relative'])
      end

      it 'uses a provided link resolver' do
        resolver = Html2rss::Scoring::LinkResolver.new('https://example.com')
        allow(resolver).to receive(:destination_facts).and_call_original

        described_class.new(Nokogiri::HTML.parse(story_html), url: 'https://example.com', link_resolver: resolver).to_a

        expect(resolver).to have_received(:destination_facts).at_least(:once)
      end
    end
  end

  describe '#document' do
    let(:provided_document) do
      Html2rss::SST::Normalizer.call(Nokogiri::HTML.parse(<<~HTML))
        <html><body><article><h2><a href="/news/provided">Provided story</a></h2>
        <p>Useful context paragraph for readers this week.</p></article></body></html>
      HTML
    end

    it 'uses the provided SST document instead of normalizing the body' do
      articles = described_class.new(nil, url: 'https://example.com', document: provided_document).to_a

      expect(articles.map { _1.url.to_s }).to eq(['https://example.com/news/provided'])
    end

    it 'normalizes the parsed body when no document is provided' do
      parsed_body = Nokogiri::HTML.parse(<<~HTML)
        <html><body><article><h2><a href="/news/parsed">Parsed story</a></h2>
        <p>Useful context paragraph for readers this week.</p></article></body></html>
      HTML

      articles = described_class.new(parsed_body, url: 'https://example.com').to_a

      expect(articles.map { _1.url.to_s }).to eq(['https://example.com/news/parsed'])
    end
  end

  describe '#articles' do
    let(:parsed_body) do
      Nokogiri::HTML.parse <<~HTML
        <html><body><article><h2><a href="/news/tagged">Tagged story</a></h2>
        <p>Useful context paragraph for readers this week.</p></article></body></html>
      HTML
    end

    it 'stamps each article with the semantic scraper class', :aggregate_failures do
      articles = described_class.new(parsed_body, url: 'https://example.com').to_a

      expect(articles).not_to be_empty
      expect(articles.map(&:scraper).uniq).to eq([described_class])
    end

    it 'collapses containers that point at the same destination' do
      duplicated = Nokogiri::HTML.parse <<~HTML
        <html><body>
          <article><h2><a href="/news/dup">Duplicate story</a></h2><p>Useful context paragraph for readers.</p></article>
          <article><h2><a href="/news/dup">Duplicate story</a></h2></article>
        </body></html>
      HTML

      articles = described_class.new(duplicated, url: 'https://example.com').to_a

      expect(articles.map { _1.url.to_s }).to eq(['https://example.com/news/dup'])
    end

    it 'ships each card its own episode file links, in noscript too, and never the navigation livestream' do
      episodes = Nokogiri::HTML.parse <<~HTML
        <html><body>
          <header><nav><a href="/live/radio.mp3">Listen live</a><a href="/podcasts/">All podcasts</a></nav></header>
          <main>
            <article><h2><a href="/podcasts/one">Episode one of the harbor show</a></h2>
              <p>Useful context paragraph for listeners this week.</p>
              <a href="/audio/one.MP3?src=list" download>Download</a></article>
            <article><h2><a href="/podcasts/two">Episode two of the harbor show</a></h2>
              <p>Useful context paragraph for listeners next week.</p>
              <noscript><p><a href="/audio/two.m4a">Download episode</a></p></noscript></article>
          </main>
        </body></html>
      HTML

      articles = described_class.new(episodes, url: 'https://example.com').to_a

      expect(articles.to_h { [_1.url.to_s, _1.enclosures.map { |e| [e.url.to_s, e.type] }] }).to eq(
        'https://example.com/podcasts/one' => [%w[https://example.com/audio/one.MP3?src=list audio/mpeg]],
        'https://example.com/podcasts/two' => [%w[https://example.com/audio/two.m4a audio/mp4]]
      )
    end
  end

  describe '#each' do
    subject(:new) { described_class.new(Nokogiri::HTML.parse(html), url: 'https://example.com') }

    let(:html) do
      cards = (1..60).map do |n|
        <<~HTML
          <article class="teaser">
            <a href="/2026/harbor-story-#{n}/"><img src="https://img.example.net/harbor-story-#{n}.jpg" alt=""></a>
            <h2><a href="/2026/harbor-story-#{n}/">Harbor crews finish repair stage #{n}</a></h2>
            <p>Work on the pier moved ahead this week as crews closed out stage #{n} of the repairs.</p>
            <div class="byline">By <a href="/author/sam-writer/">Sam Writer</a></div>
          </article>
        HTML
      end
      <<~HTML
        <html><body>
          <header><nav><a href="/">Home</a></nav></header>
          <main>
            #{cards.join}
            <div class="newsletter"><a href="https://newsletters.example.net/signup?list=weekly">Sign up for the weekly newsletter</a></div>
          </main>
        </body></html>
      HTML
    end
    let(:articles) { new.each.to_a }
    let(:article_ids) { articles.filter_map(&:id) }

    it 'yields the full article shape from a teaser card', :aggregate_failures do
      expect(articles.first).to have_attributes(
        title: 'Harbor crews finish repair stage 1',
        url: Html2rss::Url.from_absolute('https://example.com/2026/harbor-story-1/'),
        id: '/2026/harbor-story-1/'
      )
      expect(articles.first.image.to_s).to eq('https://img.example.net/harbor-story-1.jpg')
      expect(articles.first.description)
        .to eq("Work on the pier moved ahead this week as crews closed out stage 1 of the repairs.\nBy Sam Writer")
    end

    it 'keeps newsletter and author links out of the articles' do
      expect(article_ids.grep(%r{/author/|newsletters})).to be_empty
    end

    it 'yields every teaser once without fragment urls', :aggregate_failures do
      expect(article_ids).to eq((1..60).map { "/2026/harbor-story-#{_1}/" })
      expect(articles.map { _1.url.to_s }).to all(satisfy { |url| !url.include?('#') })
    end
  end
end

# rubocop:enable RSpec/ExampleLength
