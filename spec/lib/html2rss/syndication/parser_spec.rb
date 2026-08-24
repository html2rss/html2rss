# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength

require 'spec_helper'

RSpec.describe Html2rss::Syndication::Parser do
  describe '.parse' do
    it 'parses RSS 2.0 items into article hashes', :aggregate_failures do
      body = <<~XML
        <?xml version="1.0"?>
        <rss version="2.0">
          <channel>
            <title>Channel</title>
            <link>https://example.com/</link>
            <description>Desc</description>
            <item>
              <title>First</title>
              <link>https://example.com/posts/1</link>
              <description>Hello</description>
              <guid>post-1</guid>
              <pubDate>Mon, 01 Jan 2024 12:00:00 GMT</pubDate>
              <author>Ada</author>
              <category>News</category>
            </item>
          </channel>
        </rss>
      XML

      articles = described_class.parse(body)

      expect(articles.size).to eq(1)
      expect(articles.first).to include(
        id: 'post-1',
        title: 'First',
        description: 'Hello',
        author: 'Ada',
        categories: ['News']
      )
      expect(articles.first[:url].to_s).to eq('https://example.com/posts/1')
    end

    it 'parses Atom entries into article hashes', :aggregate_failures do
      body = <<~XML
        <?xml version="1.0"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Feed</title>
          <entry>
            <id>urn:example:1</id>
            <title>Entry</title>
            <link href="https://example.com/e/1" rel="alternate"/>
            <summary>Summary</summary>
            <updated>2024-02-01T00:00:00Z</updated>
            <author><name>Bea</name></author>
            <category term="Release"/>
          </entry>
        </feed>
      XML

      articles = described_class.parse(body)

      expect(articles.size).to eq(1)
      expect(articles.first).to include(
        id: 'urn:example:1',
        title: 'Entry',
        description: 'Summary',
        author: 'Bea',
        categories: ['Release']
      )
      expect(articles.first[:url].to_s).to eq('https://example.com/e/1')
    end

    it 'returns an empty array for unparseable bodies' do
      expect(described_class.parse('not xml at all <<<')).to eq([])
    end
  end

  describe '.parse_response' do
    it 'parses a syndication Response' do
      response = Html2rss::RequestService::Response.new(
        body: <<~XML,
          <?xml version="1.0"?>
          <rss version="2.0">
            <channel>
              <title>Channel</title>
              <link>https://example.com/</link>
              <description>d</description>
              <item>
                <title>Item</title>
                <link>https://example.com/i</link>
              </item>
            </channel>
          </rss>
        XML
        headers: { 'content-type' => 'application/rss+xml' },
        url: Html2rss::Url.from_absolute('https://example.com/feed.xml')
      )

      expect(described_class.parse_response(response).first[:title]).to eq('Item')
    end

    it 'raises when the response is not a feed' do
      response = Html2rss::RequestService::Response.new(
        body: '<!DOCTYPE html><html></html>',
        headers: { 'content-type' => 'text/html' },
        url: Html2rss::Url.from_absolute('https://example.com/')
      )

      expect { described_class.parse_response(response) }.to raise_error(ArgumentError, /syndication feed/)
    end
  end
end

# rubocop:enable RSpec/ExampleLength
