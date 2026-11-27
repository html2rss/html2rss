# frozen_string_literal: true

require_relative '../../support/saved_responses'

EXTRACTION_FEED_DIR = 'spec/fixtures/auto_source/corpus/t6_feed_merge'
NOW_ISO = '2026-11-20T12:00:00Z'
EXTRACTION_FEED_JSON = '{"version":"https://jsonfeed.org/version/1.1","items":[{"title":"Harbor library plans a ' \
                       'summer reading room","content_text":"Residents will read all summer long here",' \
                       '"url":"https://example.com/news/harbor-library-plans-summer"}]}'
EXTRACTION_FEED_ID = 'advertised_feed https://example.com/news/feed.xml'

RSpec.describe Html2rss::Extraction do
  let(:html) { File.read('spec/fixtures/news_front_page.html') }
  let(:url) { 'https://example.com/' }

  describe '.call' do
    subject(:result) { described_class.call(page:, now: NOW_ISO) }

    let(:page) { { url:, body: html } }

    it 'returns the articles the local-file scrape returns', :aggregate_failures do
      scraped = Html2rss.scrape(url, strategy: :local_file, local_file_path: 'spec/fixtures/news_front_page.html')

      expect(result).to have_attributes(status: :ok, error_kind: nil)
      expect(result.articles.map { |article| article[:url] }).to eq(scraped.to_rss.items.map(&:link))
      expect(result.articles.size).to eq(50)
    end

    it 'names the scraper that matched each article' do
      expect(result.articles.map { |article| article[:scraper] }.uniq).to all(start_with('AutoSource::'))
    end

    it 'holds plain values only' do
      expect(JSON.parse(JSON.generate(result.articles), symbolize_names: true)).to eq(result.articles)
    end

    it 'lets an explicit channel language win over the page language' do
      allow(Html2rss::Vocabulary).to receive(:[]).and_call_original
      response = Html2rss::RequestService::Response.local_html(body: html.sub('<html', '<html lang="de"'), url:)

      described_class.run(response:, auto_source: Html2rss::AutoSource::DEFAULT_CONFIG, clock: clock_for(nil),
                          responses: {}, channel: { language: 'fr' })

      expect(Html2rss::Vocabulary).to have_received(:[]).with('fr')
    end

    it 'reads the page language for the heuristics' do
      allow(Html2rss::Vocabulary).to receive(:[]).and_call_original

      described_class.call(page: { url:, body: html.sub('<html', '<html lang="de"') }, now: NOW_ISO)

      expect(Html2rss::Vocabulary).to have_received(:[]).with('de')
    end

    it 'dates an undated article from its URL path' do
      body = harbor_card('/news/2024/05/12/harbor-library-plans-summer')
      articles = described_class.call(page: { url:, body: }, now: NOW_ISO).articles

      expect(articles.filter_map { _1[:published_at] }).to all(start_with('2024-05-12'))
    end

    it 'passes the options to the auto-source run' do
      allow(Html2rss::AutoSource).to receive(:new).and_call_original
      cleanup = { keep_sponsored: true, keep_different_domain: true }

      described_class.call(page:, now: NOW_ISO, limit: 3, **cleanup)

      expect(Html2rss::AutoSource).to have_received(:new)
        .with(anything, hash_including(limit: 3, cleanup:), exchange: anything, vocabulary: anything, clock: anything)
    end

    it 'deduplicates the articles the scrapers return' do
      article = Html2rss::Article.new(url: 'https://example.com/a', title: 'A')
      source = instance_double(Html2rss::AutoSource, articles: [article, article], admission_drops: {},
                                                     feed_channel: nil)
      allow(Html2rss::AutoSource).to receive(:new).and_return(source)

      expect(described_class.call(page:, now: NOW_ISO).articles.size).to eq(1)
    end

    it 'strips tracking params from the item URLs' do
      body = harbor_card('/news/harbor-library-plans-summer?utm_source=feed')
      urls = described_class.call(page: { url:, body: }, now: NOW_ISO).articles.map { _1[:url] }

      expect(urls).to all(satisfy { !_1.include?('utm_') })
    end

    it 'keeps the requested limit' do
      expect(described_class.call(page:, now: NOW_ISO, limit: 3).articles.size).to eq(3)
    end

    it 'reports a page without articles as empty' do
      expect(described_class.call(page: { url:, body: '<html><body><p>nothing</p></body></html>' }, now: NOW_ISO))
        .to have_attributes(status: :empty, articles: [])
    end

    it 'returns a failure as an error kind', :aggregate_failures do
      result = described_class.call(page: { url: 'not a url', body: html }, now: NOW_ISO)

      expect(result).to have_attributes(status: :error, articles: [], error_kind: Html2rss::ErrorKind[:invalid_url])
    end

    it 'reads a date the page leaves without a year in the year of now', :aggregate_failures do
      body = harbor_card('/news/harbor-library-plans-summer', '<time datetime="12 Jul 10:30">12 Jul</time>')
      dates = ->(at) { described_class.call(page: { url:, body: }, now: at).articles.map { _1[:published_at] } }

      expect(dates.call(NOW_ISO)).to eq(['2026-07-12T10:30:00+00:00'])
      expect(dates.call('2031-01-01T00:00:00Z')).to eq(['2031-07-12T10:30:00+00:00'])
    end

    it 'reads the page headers, so a JSON feed reaches the JSON scraper' do
      feed = { url: 'https://example.com/feed.json', body: EXTRACTION_FEED_JSON,
               headers: { 'content-type' => 'application/feed+json' } }

      expect(described_class.call(page: feed, now: NOW_ISO).articles.map { _1[:url] })
        .to eq(['https://example.com/news/harbor-library-plans-summer'])
    end

    it 'raises on a now that is not an ISO 8601 time' do
      expect { described_class.call(page:, now: 'yesterday') }.to raise_error(Html2rss::InvalidOption, /yesterday/)
    end

    context 'with a page that advertises a native feed' do
      let(:page) { { url: 'https://example.com/news/', body: File.read("#{EXTRACTION_FEED_DIR}.html") } }
      let(:recorded) do
        { EXTRACTION_FEED_ID => { url: 'https://example.com/news/feed.xml', status: 200,
                                  headers: { 'content-type' => 'application/rss+xml' },
                                  body: File.read("#{EXTRACTION_FEED_DIR}/feed.xml") } }
      end

      it 'asks for the feed instead of reading it', :aggregate_failures do
        result = described_class.call(page:, now: NOW_ISO)

        expect(result).to have_attributes(status: :needs_requests, articles: [])
        expect(result.requests).to eq([{ id: EXTRACTION_FEED_ID, url: 'https://example.com/news/feed.xml',
                                         relation: :advertised_feed, origin_url: 'https://example.com/news/' }])
      end

      it 'replays the recorded exchange to the articles the gem path reads', :aggregate_failures do
        gem_path = AutoSourceCorpus.extraction(path: "#{EXTRACTION_FEED_DIR}.html", url: page[:url],
                                               request_session: SavedResponses.new(EXTRACTION_FEED_DIR))
        result = described_class.call(page:, now: NOW_ISO, responses: recorded)

        expect(result.articles.map { _1[:url] }.sort).to eq(gem_path.articles.map { _1.url.to_s }.sort)
        expect(result.articles.map { _1[:scraper] }).to include('AutoSource::NativeFeed')
      end

      it 'returns the same data for the same inputs' do
        calls = Array.new(2) { described_class.call(page:, now: NOW_ISO, responses: recorded) }

        expect(calls.uniq.size).to eq(1)
      end

      it 'carries the channel facts of the feed it read' do
        response = Html2rss::RequestService::Response.local_html(body: page[:body], url: page[:url])
        config = Html2rss::AutoSource::DEFAULT_CONFIG
        outcome = described_class.run(response:, auto_source: config, clock: clock_for(nil), responses: recorded)

        expect(outcome.feed_channel).to be_a(Html2rss::Syndication::ChannelFacts)
      end

      it 'reads a failed request as no feed, and the page items remain', :aggregate_failures do
        failed = { EXTRACTION_FEED_ID => { error_kind: :connection } }
        result = described_class.call(page:, now: NOW_ISO, responses: failed)

        expect(result.status).to eq(:ok)
        expect(result.articles.map { _1[:scraper] }).not_to include('AutoSource::NativeFeed')
      end
    end

    it 'raises on an invalid option' do
      expect { described_class.call(page:, now: NOW_ISO, limit: 0) }.to raise_error(Html2rss::InvalidOption)
    end
  end

  describe '.unique' do
    let(:articles) do
      [Html2rss::Article.new(url: 'https://example.com/a', title: 'A'),
       Html2rss::Article.new(url: 'https://example.com/a', title: 'A again'),
       Html2rss::Article.new(url: 'https://example.com/b', title: 'B'),
       Html2rss::Article.new(url: 'https://example.com/c', title: 'C')]
    end

    it 'drops duplicates and keeps the first limit articles', :aggregate_failures do
      expect(described_class.unique(articles, limit: nil).map(&:title)).to eq(%w[A B C])
      expect(described_class.unique(articles, limit: 2).map(&:title)).to eq(%w[A B])
      expect(described_class.unique(articles).map(&:title)).to eq(%w[A B C])
    end
  end

  describe '.without_tracking' do
    let(:tracked) { Html2rss::Article.new(url: 'https://example.com/a?utm_source=x&id=1', title: 'A') }
    let(:clean) { Html2rss::Article.new(url: 'https://example.com/b', title: 'B') }
    let(:linkless) { Html2rss::Article.new(title: 'C') }

    it 'strips tracking params from item URLs and keeps untouched articles as they are', :aggregate_failures do
      result = described_class.without_tracking([tracked, clean, linkless])

      expect(result.map { _1.url&.to_s }).to eq(['https://example.com/a?id=1', 'https://example.com/b', nil])
      expect(result.drop(1)).to eq([clean, linkless])
      expect(result.last).to equal(linkless)
    end
  end

  describe '.with_url_dates' do
    let(:dated) { Html2rss::Article.new(url: 'https://example.com/2024/05/12/a', published_at: '2020-01-01T00:00:00+00:00') }
    let(:undated) { Html2rss::Article.new(url: 'https://example.com/2024/05/13/b') }
    let(:no_date_in_url) { Html2rss::Article.new(url: 'https://example.com/c') }

    it 'dates only the articles without a date whose URL names one', :aggregate_failures do
      result = described_class.with_url_dates([dated, undated, no_date_in_url], clock_for('UTC'))

      expect(result.map { _1.published_at&.iso8601 })
        .to eq(['2020-01-01T00:00:00+00:00', '2024-05-13T00:00:00+00:00', nil])
      expect([result.first, result.last]).to eq([dated, no_date_in_url])
      expect(result.last).to equal(no_date_in_url)
    end

    it 'reads the URL date in the given time zone' do
      expect(described_class.with_url_dates([undated], clock_for('Asia/Tokyo')).first.published_at.iso8601)
        .to eq('2024-05-13T00:00:00+09:00')
    end
  end

  describe 'load isolation' do
    let(:script) do
      <<~RUBY
        require 'html2rss'
        html = File.read('spec/fixtures/news_front_page.html')
        r = Html2rss::Extraction.call(page: { body: html, url: 'https://example.com/' }, now: '2026-11-20T12:00:00Z')
        puts r.articles.size, $LOADED_FEATURES
      RUBY
    end
    let(:features) do
      out, status = Open3.capture2e(RbConfig.ruby, '-Ilib', '-e', script)
      raise out unless status.success?

      out.lines.map(&:chomp).drop(1)
    end

    it 'runs one extraction without loading the network or server stack' do
      forbidden = Regexp.union(
        %r{/(?:httpx|mcp|thor|rack|rackup|webrick|brotli)-[\d.]+/lib/},
        %r{(?:^|/)(?:socket|openssl|io/wait)\.(?:rb|so|bundle)$}, %r{/openssl/}
      )

      expect(features.grep(forbidden)).to eq([])
    end
  end
end
