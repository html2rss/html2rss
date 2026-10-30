# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength

require 'spec_helper'

RSpec.describe Html2rss::AutoSource::Scraper::NativeFeed do
  let(:page_url) { Html2rss::Url.from_absolute('https://example.com/blog/') }
  let(:parsed_body) do
    Nokogiri::HTML(<<~HTML)
      <html><head>
        <link rel="alternate" type="application/rss+xml" href="/feed.xml" title="Blog">
      </head>
      <body>
        <article><h1><a href="/posts/1">Structured title</a></h1></article>
      </body></html>
    HTML
  end

  describe '.options_key' do
    it { expect(described_class.options_key).to eq(:native_feed) }
  end

  describe '.request_slots' do
    it 'reserves one follow-up slot for discovery/fetch' do
      expect(described_class.request_slots({})).to eq(1)
    end
  end

  describe '.articles?' do
    it 'claims pages that advertise a syndication alternate' do
      expect(described_class.articles?(parsed_body)).to be true
    end

    it 'claims href-shaped alternates that FeedLink mime filtering skips' do
      doc = Nokogiri::HTML(<<~HTML)
        <html><head>
          <link rel="alternate" type="text/xml" href="/blog/feed.xml">
        </head></html>
      HTML

      expect(described_class.articles?(doc)).to be true
    end

    it 'does not claim pages without feed hints' do
      doc = Nokogiri::HTML('<html><body><p>No feeds</p></body></html>')
      expect(described_class.articles?(doc)).to be false
    end

    it 'does not claim non-document bodies' do
      expect(described_class.articles?(nil)).to be false
    end

    it 'does not claim a raw HTML string that carries a feed hint' do
      html = '<link rel="alternate" type="application/rss+xml" href="/feed.xml">'

      expect(described_class.articles?(html)).to be false
    end

    it 'does not claim alternates that are neither feed-typed nor feed-shaped' do
      doc = Nokogiri::HTML('<html><head><link rel="alternate" type="text/html" href="/about"></head></html>')

      expect(described_class.articles?(doc)).to be false
    end
  end

  describe '#extractable?' do
    it 'delegates to articles? for the parsed body' do
      expect(described_class.new(parsed_body, url: page_url)).to be_extractable
    end

    it 'is false for a body without feed hints' do
      doc = Nokogiri::HTML('<html><body><p>No feeds</p></body></html>')

      expect(described_class.new(doc, url: page_url)).not_to be_extractable
    end
  end

  describe '#initialize' do
    let(:session) { instance_double(Html2rss::RequestSession) }

    it 'forwards the parsed body and an absolute Url to discovery', :aggregate_failures do
      allow(Html2rss::Syndication::Discovery).to receive(:best_feed_response).and_return(nil)

      described_class.new(parsed_body, url: 'https://example.com/blog/', request_session: session).to_a

      expect(Html2rss::Syndication::Discovery).to have_received(:best_feed_response).with(
        hash_including(page_url: Html2rss::Url.from_absolute('https://example.com/blog/'), parsed_body:)
      )
    end
  end

  describe '#fetch_articles' do
    let(:session) { instance_double(Html2rss::RequestSession) }

    it 'passes the session, body, url and request slots to discovery', :aggregate_failures do
      allow(Html2rss::Syndication::Discovery).to receive(:best_feed_response).and_return(nil)

      described_class.new(parsed_body, url: page_url, request_session: session).to_a

      expect(Html2rss::Syndication::Discovery).to have_received(:best_feed_response).with(
        page_url:, request_session: session, parsed_body:, max_probes: 1
      )
    end

    it 'does not run discovery without a request session', :aggregate_failures do
      allow(Html2rss::Syndication::Discovery).to receive(:best_feed_response)

      expect(described_class.new(parsed_body, url: page_url).to_a).to eq([])
      expect(Html2rss::Syndication::Discovery).not_to have_received(:best_feed_response)
    end
  end

  describe '#each' do
    let(:session) { instance_double(Html2rss::RequestSession) }
    let(:feed_body) do
      <<~XML
        <?xml version="1.0"?>
        <rss version="2.0">
          <channel>
            <title>Blog</title>
            <link>https://example.com/</link>
            <description>d</description>
            <item>
              <title>From feed</title>
              <link>https://example.com/posts/from-feed</link>
              <description>Native item</description>
            </item>
          </channel>
        </rss>
      XML
    end
    let(:feed_response) do
      Html2rss::RequestService::Response.new(
        body: feed_body,
        headers: { 'content-type' => 'application/rss+xml' },
        url: Html2rss::Url.from_absolute('https://example.com/feed.xml'),
        status: 200
      )
    end

    it 'yields articles parsed from the discovered native feed', :aggregate_failures do
      allow(session).to receive(:follow_up).and_return(feed_response)

      articles = described_class.new(parsed_body, url: page_url, request_session: session).to_a

      expect(articles.size).to eq(1)
      expect(articles.first[:title]).to eq('From feed')
      expect(articles.first[:url].to_s).to eq('https://example.com/posts/from-feed')
    end

    it 'returns an enumerator without a block' do
      expect(described_class.new(parsed_body, url: page_url, request_session: session).each).to be_a(Enumerator)
    end

    it 'logs and yields nothing when discovery finds no feed', :aggregate_failures do
      allow(Html2rss::Log).to receive(:info)
      allow(Html2rss::Syndication::Discovery).to receive(:best_feed_response).and_return(nil)

      articles = described_class.new(parsed_body, url: page_url, request_session: session).to_a

      expect(articles).to eq([])
      expect(Html2rss::Syndication::Discovery).to have_received(:best_feed_response).with(
        hash_including(max_probes: described_class.request_slots)
      )
      expect(Html2rss::Log).to have_received(:info).with(
        a_string_including('item_count=0', 'fallback=true')
      )
    end

    it 'swallows discovery errors and yields nothing', :aggregate_failures do
      allow(Html2rss::Log).to receive(:warn)
      allow(Html2rss::Syndication::Discovery).to receive(:best_feed_response)
        .and_raise(Html2rss::Error, 'Network error')

      articles = described_class.new(parsed_body, url: page_url, request_session: session).to_a

      expect(articles).to eq([])
      expect(Html2rss::Log).to have_received(:warn).with(
        a_string_including('failed (Html2rss::Error: Network error)')
      )
    end

    it 'yields nothing without a request session' do
      expect(described_class.new(parsed_body, url: page_url).to_a).to eq([])
    end

    it 'logs the items event with the discovered item count', :aggregate_failures do
      allow(Html2rss::Log).to receive(:info)
      allow(session).to receive(:follow_up).and_return(feed_response)

      described_class.new(parsed_body, url: page_url, request_session: session).to_a

      expect(Html2rss::Log).to have_received(:info).with(
        {
          event_name: 'auto_source.native_feed.items',
          host: 'example.com',
          message: 'Html2rss::AutoSource::Scraper::NativeFeed: host=example.com item_count=1 fallback=false'
        }.to_json
      )
    end

    it 'logs the empty event when discovery yields no feed', :aggregate_failures do
      allow(Html2rss::Log).to receive(:info)
      allow(Html2rss::Syndication::Discovery).to receive(:best_feed_response).and_return(nil)

      described_class.new(parsed_body, url: page_url, request_session: session).to_a

      expect(Html2rss::Log).to have_received(:info).with(
        {
          event_name: 'auto_source.native_feed.empty',
          host: 'example.com',
          message: 'Html2rss::AutoSource::Scraper::NativeFeed: host=example.com item_count=0 fallback=true'
        }.to_json
      )
    end
  end
end

# rubocop:enable RSpec/ExampleLength
