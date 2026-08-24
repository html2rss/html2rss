# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Syndication::Discovery do
  describe '.page_dir_paths' do
    it 'returns directory-relative feed guesses for nested pages' do
      expect(described_class.page_dir_paths('https://example.com/news/index.html')).to eq(
        %w[/news/feed /news/rss.xml /news/atom.xml]
      )
    end

    it 'returns no directory guesses for the origin root' do
      expect(described_class.page_dir_paths('https://example.com/')).to eq([])
    end
  end

  describe '.candidate_urls' do
    it 'prefers head alternate links from a parsed document before path guesses', :aggregate_failures do
      doc = Nokogiri::HTML(<<~HTML)
        <html><head>
          <link rel="alternate" type="application/rss+xml" href="/custom.xml">
        </head></html>
      HTML

      urls = described_class.candidate_urls(
        page_url: 'https://example.com/blog/',
        parsed_body: doc
      )

      expect(urls.first.to_s).to eq('https://example.com/custom.xml')
      expect(urls.map(&:to_s)).to include('https://example.com/feed')
    end

    it 'falls back to string HTML alternate scanning when no document is given' do
      html = '<link rel="alternate" type="application/atom+xml" href="/atom.xml">'
      urls = described_class.candidate_urls(page_url: 'https://example.com/', html:)

      expect(urls.first.to_s).to eq('https://example.com/atom.xml')
    end
  end

  describe '.feedish?' do
    def response(body:, content_type:, status: 200)
      Html2rss::RequestService::Response.new(
        body:,
        headers: { 'content-type' => content_type },
        url: Html2rss::Url.from_absolute('https://example.com/feed'),
        status:
      )
    end

    it 'accepts RSS content types' do
      expect(described_class.feedish?(response(body: '<rss', content_type: 'application/rss+xml'))).to be true
    end

    it 'accepts body sniff when content type is plain' do
      expect(
        described_class.feedish?(response(body: '<?xml version="1.0"?><rss version="2.0">', content_type: 'text/plain'))
      ).to be true
    end

    it 'rejects non-success status' do
      expect(
        described_class.feedish?(response(body: '<rss', content_type: 'application/rss+xml', status: 404))
      ).to be false
    end
  end

  describe '.best_feed_url' do
    let(:page_url) { Html2rss::Url.from_absolute('https://example.com/news/') }
    let(:session) { instance_double(Html2rss::RequestSession) }

    it 'stops at the first feedish candidate without probing further', :aggregate_failures do
      feed_response = Html2rss::RequestService::Response.new(
        body: '<?xml version="1.0"?><rss version="2.0"><channel></channel></rss>',
        headers: { 'content-type' => 'application/rss+xml' },
        url: Html2rss::Url.from_absolute('https://example.com/news/feed'),
        status: 200
      )

      allow(session).to receive(:follow_up).and_return(feed_response)

      selected = described_class.best_feed_url(
        page_url:,
        request_session: session,
        html: ''
      )

      expect(selected.to_s).to eq('https://example.com/news/feed')
      expect(session).to have_received(:follow_up).once
    end

    it 'skips probe errors and continues to the next candidate' do
      miss = Html2rss::RequestService::Response.new(
        body: 'not a feed',
        headers: { 'content-type' => 'text/html' },
        url: Html2rss::Url.from_absolute('https://example.com/news/feed'),
        status: 200
      )
      hit = Html2rss::RequestService::Response.new(
        body: '<rss version="2.0"></rss>',
        headers: { 'content-type' => 'application/rss+xml' },
        url: Html2rss::Url.from_absolute('https://example.com/news/rss.xml'),
        status: 200
      )

      allow(session).to receive(:follow_up).and_invoke(
        ->(**) { raise Html2rss::RequestService::CrossOriginFollowUpDenied, 'denied' },
        ->(**) { miss },
        ->(**) { hit }
      )

      selected = described_class.best_feed_url(page_url:, request_session: session, html: '')

      # Candidates: /news/feed (error), /news/rss.xml (miss), /news/atom.xml (hit)
      expect(selected.to_s).to eq('https://example.com/news/atom.xml')
    end
  end
end
