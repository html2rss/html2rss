# frozen_string_literal: true

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

  before do
    allow(described_class).to receive(:fetch_initial).and_return([nil, fake_response, nil])
  end

  describe '.call' do
    it 'returns a ReconResult with defer verdict when native feed is present', :aggregate_failures do
      result = described_class.call(url)
      expect(result).to be_a(Html2rss::ReconResult)
      expect(result.defer?).to be(true)
    end

    context 'without stubbed fetch_initial' do
      before do
        allow(described_class).to receive(:fetch_initial).and_call_original
        fake_session = instance_double(
          Html2rss::RequestSession,
          fetch_initial_response: fake_response,
          follow_up: fake_response
        )
        allow(Html2rss::RequestSession).to receive(:build).and_return(fake_session)
      end

      it 'invokes the real fetch_initial flow' do
        result = described_class.call(url)
        expect(result.defer?).to be(true)
      end
    end

    context 'when no native feed and articles are found' do
      let(:html_body) do
        <<~HTML
          <html>
            <head><title>News</title></head>
            <body><article><h2><a href="/post-1">Post 1</a></h2></article></body>
          </html>
        HTML
      end

      it 'returns BUILD verdict' do
        result = described_class.call(url)
        expect(result.build?).to be(true)
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

      it 'returns DROP verdict' do
        result = described_class.call('https://example.com/news')
        expect(result.drop?).to be(true)
      end
    end

    context 'when fetch raises an error' do
      before do
        allow(described_class).to receive(:fetch_initial).and_return([nil, nil,
                                                                      StandardError.new('connection refused')])
      end

      it 'returns DROP verdict with error note', :aggregate_failures do
        result = described_class.call(url)
        expect(result.drop?).to be(true)
        expect(result.notes.first).to include('connection refused')
      end
    end
  end

  describe '.batch' do
    it 'processes an array of URLs concurrently', :aggregate_failures do
      results = described_class.batch([url])
      expect(results.size).to eq(1)
      expect(results.first).to be_a(Html2rss::ReconResult)
    end

    it 'caches HTML snapshot when cache_dir is given', :aggregate_failures do
      Dir.mktmpdir do |dir|
        results = described_class.batch([url], cache_dir: dir)
        expect(results.size).to eq(1)
        expect(Dir.children(dir)).not_to be_empty
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
