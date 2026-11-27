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

    it 'names the scrapers that matched', :aggregate_failures do
      expect(result.scrapers.values.sum).to eq(50)
      expect(result.articles.map { |article| article[:scraper] }.uniq).to match_array(result.scrapers.keys)
    end

    it 'holds plain values only' do
      expect(JSON.parse(JSON.generate(result.articles), symbolize_names: true)).to eq(result.articles)
    end

    it 'keeps the requested limit' do
      expect(described_class.call(html:, url:, limit: 3).articles.size).to eq(3)
    end

    it 'reports a page without articles as empty' do
      expect(described_class.call(html: '<html><body><p>nothing</p></body></html>', url:))
        .to have_attributes(status: :empty, articles: [], scrapers: {})
    end

    it 'returns a failure as an error kind', :aggregate_failures do
      result = described_class.call(html:, url: 'not a url')

      expect(result).to have_attributes(status: :error, articles: [], error_kind: Html2rss::ErrorKind[:invalid_url])
    end

    it 'raises on an invalid option' do
      expect { described_class.call(html:, url:, limit: 0) }.to raise_error(Html2rss::InvalidOption)
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
        %r{(?:^|/)(?:openssl|io/wait)\.(?:rb|so|bundle)$}, %r{/openssl/}
      )

      expect(features.grep(forbidden)).to eq([])
    end

    it 'loads no socket', pending: 'Url requires ipaddr, which loads socket' do
      expect(features.grep(%r{(?:^|/)socket\.(?:rb|so|bundle)$})).to eq([])
    end
  end
end
