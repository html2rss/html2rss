# frozen_string_literal: true

require 'tmpdir'

# rubocop:disable-next RSpec/MultipleMemoizedHelpers -- probe/response fixtures shared across verdict contexts
RSpec.describe Html2rss::Recon do
  let(:url) { 'https://example.com/news' }
  let(:html_body) do
    <<~HTML
      <!DOCTYPE html>
      <html>
        <head>
          <title>Example News</title>
          <link rel="alternate" type="application/rss+xml" title="RSS" href="/feed.xml" />
        </head>
        <body>
          <article><h2><a href="/post-1">Post 1</a></h2></article>
        </body>
      </html>
    HTML
  end
  let(:fake_response) do
    instance_double(
      Html2rss::RequestService::Response,
      url: Html2rss::Url.from_absolute(url),
      status: 200,
      body: html_body,
      html_response?: true,
      feed_response?: false,
      captured_responses: [],
      content_type: 'text/html',
      parsed_body: Nokogiri::HTML(html_body)
    )
  end
  let(:fake_session) do
    instance_double(Html2rss::RequestSession, fetch_initial_response: fake_response, follow_up: fake_response)
  end
  let(:page_recon_result) do
    Html2rss::PageRecon.call(response: fake_response, url:)
  end
  let(:probe) do
    Html2rss::PageRecon::Probe.new(
      session: fake_session,
      response: fake_response,
      result: page_recon_result,
      strategy: :faraday
    )
  end
  let(:discovered_feed) { Html2rss::Url.from_absolute('https://example.com/feed.xml') }

  before do
    allow(Html2rss::PageRecon).to receive(:probe).and_return(probe)
    allow(Html2rss::Syndication::Discovery).to receive(:best_feed_url).and_return(discovered_feed)
  end

  describe '.call' do
    it 'returns a Recon::Result with defer verdict when Discovery finds a feed', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      result = described_class.call(url)
      expect(result).to be_a(Html2rss::Recon::Result)
      expect(result.defer?).to be(true)
      expect(result.verdict).to eq(Html2rss::Recon::Verdict.coerce(:defer))
      expect(Html2rss::PageRecon).to have_received(:probe).with(
        kind_of(Html2rss::Url), hash_including(strategy: :auto)
      )
      expect(Html2rss::Syndication::Discovery).to have_received(:best_feed_url).with(
        hash_including(request_session: fake_session, page_url: kind_of(Html2rss::Url))
      )
    end

    context 'when Discovery finds no feed and articles are present' do
      let(:html_body) do
        <<~HTML
          <html>
            <head><title>News</title></head>
            <body><article><h2><a href="/post-1">Post 1</a></h2></article></body>
          </html>
        HTML
      end
      let(:discovered_feed) { nil }

      it 'returns BUILD verdict and does not fall back to PageRecon alternates' do
        result = described_class.call(url)
        expect(result.build?).to be(true)
      end
    end

    context 'when Discovery raises an error' do
      let(:html_body) do
        <<~HTML
          <html>
            <head><title>News</title></head>
            <body><article><h2><a href="/post-1">Post 1</a></h2></article></body>
          </html>
        HTML
      end
      let(:discovered_feed) { nil }

      before do
        allow(Html2rss::Syndication::Discovery).to receive(:best_feed_url)
          .and_raise(StandardError.new('timeout'))
      end

      it 'records a discovery_error note and keeps BUILD verdict', :aggregate_failures do
        result = described_class.call(url)
        expect(result.build?).to be(true)
        expect(result.notes).to include('discovery_error=StandardError: timeout')
      end
    end

    context 'when HTTP status is 404' do
      let(:fake_response) do
        instance_double(
          Html2rss::RequestService::Response,
          url: Html2rss::Url.from_absolute(url),
          status: 404,
          body: 'Not Found',
          html_response?: false,
          feed_response?: false,
          captured_responses: [],
          content_type: 'text/html',
          parsed_body: nil
        )
      end
      let(:discovered_feed) { nil }

      it 'returns DROP verdict' do
        result = described_class.call(url)
        expect(result.drop?).to be(true)
      end
    end

    context 'when scheme is downgraded' do
      let(:fake_response) do
        instance_double(
          Html2rss::RequestService::Response,
          url: Html2rss::Url.from_absolute('http://example.com/news'),
          status: 200,
          body: html_body,
          html_response?: true,
          feed_response?: false,
          captured_responses: [],
          content_type: 'text/html',
          parsed_body: Nokogiri::HTML(html_body)
        )
      end
      let(:discovered_feed) { nil }

      it 'returns DROP verdict' do
        result = described_class.call('https://example.com/news')
        expect(result.drop?).to be(true)
      end

      it 'includes a Botasaurus retry hint in notes', :aggregate_failures do
        result = described_class.call('https://example.com/news')
        expect(result.notes).to include('scheme_downgrade')
        expect(result.notes.join(' ')).to include('botasaurus_retry')
      end
    end

    context 'when probe raises an error' do
      before do
        allow(Html2rss::PageRecon).to receive(:probe).and_raise(StandardError.new('connection refused'))
      end

      it 'returns DROP verdict with error note', :aggregate_failures do
        result = described_class.call(url)
        expect(result.drop?).to be(true)
        expect(result.notes.first).to include('connection refused')
      end
    end
  end

  describe '.batch' do
    let(:discovered_feed) { nil }

    it 'processes an array of URLs concurrently', :aggregate_failures do
      results = described_class.batch([url])
      expect(results.size).to eq(1)
      expect(results.first).to be_a(Html2rss::Recon::Result)
    end

    it 'preserves input order across concurrent workers' do # rubocop:disable RSpec/ExampleLength
      urls = %w[
        https://example.com/a
        https://example.com/b
        https://example.com/c
      ]
      allow(described_class).to receive(:call) do |target_url, **|
        sleep(0.01) if target_url.include?('/a')
        Html2rss::Recon::Result.new(
          requested_url: Html2rss::Url.from_absolute(target_url),
          final_url: Html2rss::Url.from_absolute(target_url),
          status: 200,
          verdict: Html2rss::Recon::Verdict.coerce(:build),
          native_feed: nil,
          surface_category: Html2rss::SurfaceCategory.coerce(:article_list),
          articles_count: 1,
          scheme_downgrade: false,
          notes: [],
          html_bytesize: 10
        )
      end

      results = described_class.batch(urls, max_threads: 3)
      expect(results.map { |r| r.requested_url.to_s }).to eq(urls)
    end

    it 'caches HTML body bytes when cache_dir is given', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      Dir.mktmpdir do |dir|
        results = described_class.batch([url], cache_dir: dir)
        expect(results.size).to eq(1)
        cached = Dir.glob(File.join(dir, '*.html'))
        expect(cached).not_to be_empty
        expect(File.read(cached.first)).to include('<title>Example News</title>')
        expect(File.read(cached.first)).not_to include('native_rss=')
      end
    end

    it 'handles cache write failures gracefully' do
      Dir.mktmpdir do |dir|
        allow(File).to receive(:write).and_raise(StandardError.new('disk full'))
        expect { described_class.batch([url], cache_dir: dir) }.not_to raise_error
      end
    end
  end
end
