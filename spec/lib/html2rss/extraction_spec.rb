# frozen_string_literal: true

RSpec.describe Html2rss::Extraction do
  let(:html) { File.read('spec/fixtures/news_front_page.html') }
  let(:url) { 'https://example.com/' }

  describe '.call' do
    subject(:result) { described_class.call(html:, url:) }

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

    it 'reads the page language for the heuristics' do
      allow(Html2rss::Vocabulary).to receive(:[]).and_call_original

      described_class.call(html: html.sub('<html', '<html lang="de"'), url:)

      expect(Html2rss::Vocabulary).to have_received(:[]).with('de')
    end

    it 'dates an undated article from its URL path' do
      page = '<html><body><article><h2><a href="/news/2024/05/12/harbor-library-plans-summer">Harbor library ' \
             'plans a summer reading room</a></h2><p>Residents will read.</p></article></body></html>'

      expect(described_class.call(html: page, url:).articles.filter_map { _1[:published_at] })
        .to all(start_with('2024-05-12'))
    end

    it 'passes the options to the auto-source run' do
      allow(Html2rss::AutoSource).to receive(:new).and_call_original

      described_class.call(html:, url:, limit: 3, keep_sponsored: true, keep_different_domain: true)
      cleanup = { keep_sponsored: true, keep_different_domain: true }

      expect(Html2rss::AutoSource)
        .to have_received(:new).with(anything, hash_including(limit: 3, cleanup:), vocabulary: anything)
    end

    it 'deduplicates the articles the scrapers return' do
      article = Html2rss::Article.new(url: 'https://example.com/a', title: 'A')
      allow(Html2rss::AutoSource).to receive(:new).and_return(instance_double(Html2rss::AutoSource,
                                                                              articles: [article, article]))

      expect(described_class.call(html:, url:).articles.size).to eq(1)
    end

    it 'strips tracking params from the item URLs' do
      page = '<html><body><article><h2><a href="/news/harbor-library-plans-summer?utm_source=feed">Harbor library ' \
             'plans a summer reading room</a></h2><p>Residents will read.</p></article></body></html>'

      expect(described_class.call(html: page, url:).articles.map { _1[:url] }).to all(satisfy { !_1.include?('utm_') })
    end

    it 'keeps the requested limit' do
      expect(described_class.call(html:, url:, limit: 3).articles.size).to eq(3)
    end

    it 'reports a page without articles as empty' do
      expect(described_class.call(html: '<html><body><p>nothing</p></body></html>', url:))
        .to have_attributes(status: :empty, articles: [])
    end

    it 'returns a failure as an error kind', :aggregate_failures do
      result = described_class.call(html:, url: 'not a url')

      expect(result).to have_attributes(status: :error, articles: [], error_kind: Html2rss::ErrorKind[:invalid_url])
    end

    it 'raises on an invalid option' do
      expect { described_class.call(html:, url:, limit: 0) }.to raise_error(Html2rss::InvalidOption)
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
      result = described_class.with_url_dates([dated, undated, no_date_in_url], 'UTC')

      expect(result.map { _1.published_at&.iso8601 })
        .to eq(['2020-01-01T00:00:00+00:00', '2024-05-13T00:00:00+00:00', nil])
      expect([result.first, result.last]).to eq([dated, no_date_in_url])
      expect(result.last).to equal(no_date_in_url)
    end

    it 'reads the URL date in the given time zone' do
      expect(described_class.with_url_dates([undated], 'Asia/Tokyo').first.published_at.iso8601)
        .to eq('2024-05-13T00:00:00+09:00')
    end
  end

  describe 'load isolation' do
    let(:script) do
      <<~RUBY
        require 'html2rss'
        html = File.read('spec/fixtures/news_front_page.html')
        r = Html2rss::Extraction.call(html:, url: 'https://example.com/')
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
