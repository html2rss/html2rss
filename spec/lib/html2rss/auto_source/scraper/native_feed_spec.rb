# frozen_string_literal: true

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

  describe '.articles?' do
    it 'claims pages that advertise a syndication alternate' do
      expect(described_class.articles?(parsed_body)).to be true
    end

    it 'does not claim pages without feed hints' do
      doc = Nokogiri::HTML('<html><body><p>No feeds</p></body></html>')
      expect(described_class.articles?(doc)).to be false
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
  end
end
