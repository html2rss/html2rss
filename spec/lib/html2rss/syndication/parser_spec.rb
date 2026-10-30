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

    it 'returns an empty array for a missing body' do
      expect(described_class.parse(nil)).to eq([])
    end

    it 'returns an empty array for a document that is neither RSS nor Atom' do
      expect(described_class.parse('<html><body><p>Hello</p></body></html>')).to eq([])
    end

    it 'logs a structured warning when the body cannot be parsed' do
      allow(Html2rss::Log).to receive(:warn)

      described_class.parse('not xml at all <<<')

      expect(Html2rss::Log).to have_received(:warn).with(
        satisfy do |payload|
          event = JSON.parse(payload)
          event['event_name'] == 'syndication.parse_failed' &&
            event['error_class'] == 'RSS::NotWellFormedError' &&
            event['message'].match?(/\ASyndication::Parser: failed to parse feed \(RSS::NotWellFormedError: .+\)\z/m)
        end
      )
    end

    it 'returns no articles for RSS 1.0 documents' do
      body = <<~XML
        <?xml version="1.0"?>
        <rdf:RDF xmlns="http://purl.org/rss/1.0/" xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <channel rdf:about="https://example.com/"><title>C</title><link>https://example.com/</link><description>d</description><items><rdf:Seq/></items></channel>
          <item rdf:about="https://example.com/a"><title>A</title><link>https://example.com/a</link><description>x</description></item>
        </rdf:RDF>
      XML

      expect(described_class.parse(body)).to eq([])
    end

    it 'resolves relative RSS item links against base_url', :aggregate_failures do
      body = <<~XML
        <?xml version="1.0"?>
        <rss version="2.0"><channel><title>C</title>
          <item><title>Relative</title><link>posts/1.html</link></item>
          <item><title>Rooted</title><link>/root/2.html</link></item>
        </channel></rss>
      XML

      articles = described_class.parse(body, base_url: 'https://example.com/blog/')

      expect(articles.map { |article| article[:url].to_s }).to eq(
        ['https://example.com/blog/posts/1.html', 'https://example.com/root/2.html']
      )
    end

    it 'drops items whose link is missing, blank, or relative without a base_url', :aggregate_failures do
      body = <<~XML
        <?xml version="1.0"?>
        <rss version="2.0"><channel><title>C</title>
          <item><title>No link</title></item>
          <item><title>Blank link</title><link>   </link></item>
          <item><title>Relative</title><link>posts/2.html</link></item>
          <item><title>Kept</title><link>https://example.com/kept</link></item>
        </channel></rss>
      XML

      articles = described_class.parse(body)

      expect(articles.map { |article| article[:title] }).to eq(['Kept'])
    end

    it 'uses the article URL as id when the RSS guid is missing or blank', :aggregate_failures do
      body = <<~XML
        <?xml version="1.0"?>
        <rss version="2.0"><channel><title>C</title>
          <item><title>No guid</title><link>https://example.com/a</link></item>
          <item><title>Blank guid</title><link>https://example.com/b</link><guid>   </guid></item>
        </channel></rss>
      XML

      ids = described_class.parse(body).map { |article| article[:id] }

      expect(ids).to eq(%w[https://example.com/a https://example.com/b])
    end

    it 'omits absent optional RSS fields instead of emitting nil or empty values', :aggregate_failures do
      body = <<~XML
        <?xml version="1.0"?>
        <rss version="2.0"><channel><title>C</title>
          <item><link>https://example.com/bare</link></item>
        </channel></rss>
      XML

      article = described_class.parse(body).first

      expect(article.keys).to contain_exactly(:id, :url, :categories)
      expect(article).to include(id: 'https://example.com/bare', categories: [])
    end

    it 'strips surrounding whitespace from RSS text fields and drops whitespace-only ones', :aggregate_failures do
      body = <<~XML
        <?xml version="1.0"?>
        <rss version="2.0"><channel><title>C</title>
          <item>
            <title>  Padded title  </title>
            <link>https://example.com/p</link>
            <description>   </description>
            <author>  Ada  </author>
            <guid>  g-1 </guid>
          </item>
        </channel></rss>
      XML

      article = described_class.parse(body).first

      expect(article).to include(title: 'Padded title', author: 'Ada', id: 'g-1')
      expect(article).not_to have_key(:description)
    end

    it 'reads published_at from the RSS pubDate' do
      body = <<~XML
        <?xml version="1.0"?>
        <rss version="2.0"><channel><title>C</title>
          <item><title>Dated</title><link>https://example.com/d</link><pubDate>Mon, 01 Jan 2024 12:00:00 GMT</pubDate></item>
        </channel></rss>
      XML

      expect(described_class.parse(body).first[:published_at]).to eq(Time.utc(2024, 1, 1, 12))
    end

    it 'keeps only non-blank RSS category names', :aggregate_failures do
      body = <<~XML
        <?xml version="1.0"?>
        <rss version="2.0"><channel><title>C</title>
          <item>
            <title>Tagged</title><link>https://example.com/t</link>
            <category>News</category><category>   </category><category>Tech</category>
          </item>
        </channel></rss>
      XML

      expect(described_class.parse(body).first[:categories]).to eq(%w[News Tech])
    end

    it 'prefers the Atom alternate link over self links', :aggregate_failures do
      body = <<~XML
        <?xml version="1.0"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Feed</title>
          <entry>
            <id>urn:example:alt</id>
            <title>Alt</title>
            <link rel="self" href="https://example.com/self/alt.atom"/>
            <link rel="alternate" href="https://example.com/e/alt"/>
          </entry>
          <entry>
            <id>urn:example:self</id>
            <title>Self only</title>
            <link rel="self" href="https://example.com/self/only.atom"/>
          </entry>
        </feed>
      XML

      urls = described_class.parse(body).map { |article| article[:url].to_s }

      expect(urls).to eq(%w[https://example.com/e/alt https://example.com/self/only.atom])
    end

    it 'resolves relative Atom links against base_url and drops them without one', :aggregate_failures do
      body = <<~XML
        <?xml version="1.0"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Feed</title>
          <entry><id>urn:example:rel</id><title>Relative</title><link href="entries/3"/></entry>
        </feed>
      XML

      with_base = described_class.parse(body, base_url: 'https://example.com/blog/')
      without_base = described_class.parse(body)

      expect(with_base.first[:url].to_s).to eq('https://example.com/blog/entries/3')
      expect(without_base).to eq([])
    end

    it 'picks the first rel-less link over a later self link', :aggregate_failures do
      body = <<~XML
        <?xml version="1.0"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Feed</title>
          <entry><id>urn:example:order</id>
            <link rel="self" href="https://example.com/self/order.atom"/>
            <link href="https://example.com/plain"/>
            <link rel="alternate" href="https://example.com/alt/1"/>
            <link rel="alternate" href="https://example.com/alt/2"/>
          </entry>
        </feed>
      XML

      expect(described_class.parse(body).first[:url].to_s).to eq('https://example.com/plain')
    end

    it 'treats a blank Atom href as no link', :aggregate_failures do
      body = <<~XML
        <?xml version="1.0"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Feed</title>
          <entry><id>urn:example:blank</id><link href="   "/></entry>
        </feed>
      XML

      expect(described_class.parse(body, base_url: 'https://example.com/')).to eq([])
    end

    it 'treats blank Atom id, title, and summary as absent', :aggregate_failures do
      body = <<~XML
        <?xml version="1.0"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Feed</title>
          <entry><id>   </id><title>   </title><link href="https://example.com/blank"/><summary>   </summary></entry>
        </feed>
      XML

      article = described_class.parse(body).first

      expect(article[:id]).to eq('https://example.com/blank')
      expect(article.keys).to contain_exactly(:id, :url, :categories)
    end

    it 'uses the Atom author name alone and omits a blank email or an empty author', :aggregate_failures do
      body = <<~XML
        <?xml version="1.0"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Feed</title>
          <entry><id>urn:example:name</id><link href="https://example.com/name"/>
            <author><name>Ada</name></author></entry>
          <entry><id>urn:example:blank-mail</id><link href="https://example.com/bm"/>
            <author><name>   </name><email>   </email></author></entry>
          <entry><id>urn:example:empty</id><link href="https://example.com/empty"/>
            <author></author></entry>
        </feed>
      XML

      authors = described_class.parse(body).map { |article| article[:author] }

      expect(authors).to eq(['Ada', nil, nil])
    end

    it 'drops Atom entries that carry no link', :aggregate_failures do
      body = <<~XML
        <?xml version="1.0"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Feed</title>
          <entry><id>urn:example:nolink</id><title>No link</title></entry>
        </feed>
      XML

      expect(described_class.parse(body)).to eq([])
    end

    it 'falls back to updated when Atom published is missing, and prefers published otherwise', :aggregate_failures do
      body = <<~XML
        <?xml version="1.0"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Feed</title>
          <entry><id>urn:example:u</id><link href="https://example.com/u"/><updated>2024-02-01T00:00:00Z</updated></entry>
          <entry><id>urn:example:p</id><link href="https://example.com/p"/>
            <published>2024-03-01T00:00:00Z</published><updated>2024-03-05T00:00:00Z</updated></entry>
        </feed>
      XML

      published = described_class.parse(body).map { |article| article[:published_at] }

      expect(published).to eq([Time.utc(2024, 2, 1), Time.utc(2024, 3, 1)])
    end

    it 'prefers Atom content over summary and falls back to summary', :aggregate_failures do
      body = <<~XML
        <?xml version="1.0"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Feed</title>
          <entry><id>urn:example:c</id><link href="https://example.com/c"/>
            <summary>Short</summary><content type="text">Full body</content></entry>
          <entry><id>urn:example:s</id><link href="https://example.com/s"/><summary>Only summary</summary></entry>
        </feed>
      XML

      descriptions = described_class.parse(body).map { |article| article[:description] }

      expect(descriptions).to eq(['Full body', 'Only summary'])
    end

    it 'omits a missing Atom title and a missing Atom id falls back to the URL', :aggregate_failures do
      body = <<~XML
        <?xml version="1.0"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Feed</title>
          <entry><link href="https://example.com/untitled"/></entry>
        </feed>
      XML

      article = described_class.parse(body).first

      expect(article).not_to have_key(:title)
      expect(article[:id]).to eq('https://example.com/untitled')
    end

    it 'falls back to the Atom author email when the name is blank', :aggregate_failures do
      body = <<~XML
        <?xml version="1.0"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Feed</title>
          <entry><id>urn:example:mail</id><link href="https://example.com/m"/>
            <author><name>   </name><email>ada@example.com</email></author></entry>
          <entry><id>urn:example:none</id><link href="https://example.com/n"/></entry>
        </feed>
      XML

      authors = described_class.parse(body).map { |article| article[:author] }

      expect(authors).to eq(['ada@example.com', nil])
      expect(described_class.parse(body).last).not_to have_key(:author)
    end

    it 'keeps only non-blank Atom category terms' do
      body = <<~XML
        <?xml version="1.0"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Feed</title>
          <entry><id>urn:example:cat</id><link href="https://example.com/cat"/>
            <category term="Release"/><category term="  "/></entry>
        </feed>
      XML

      expect(described_class.parse(body).first[:categories]).to eq(['Release'])
    end

    it 'reads Atom text from content, not serialized XML', :aggregate_failures do
      body = <<~XML
        <?xml version="1.0"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Feed</title>
          <entry>
            <id>urn:example:xhtml</id>
            <title>Entry</title>
            <link href="https://example.com/e/xhtml" rel="alternate"/>
            <content type="xhtml"><div xmlns="http://www.w3.org/1999/xhtml">Inner</div></content>
          </entry>
        </feed>
      XML

      article = described_class.parse(body).first

      expect(article[:description]).to eq('<div xmlns="http://www.w3.org/1999/xhtml">Inner</div>')
      expect(article[:description]).not_to include('<content')
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

    it 'resolves relative item links against the response URL' do
      response = Html2rss::RequestService::Response.new(
        body: <<~XML,
          <?xml version="1.0"?>
          <rss version="2.0"><channel><title>C</title>
            <item><title>Relative</title><link>posts/1.html</link></item>
          </channel></rss>
        XML
        headers: { 'content-type' => 'application/rss+xml' },
        url: Html2rss::Url.from_absolute('https://example.com/blog/feed.xml')
      )

      expect(described_class.parse_response(response).first[:url].to_s).to eq('https://example.com/blog/posts/1.html')
    end
  end
end

# rubocop:enable RSpec/ExampleLength
