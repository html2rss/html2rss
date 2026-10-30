# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable RSpec/ExampleLength
SITEMAP_SPEC_LINK_HTML = '<html><head><link rel="sitemap" href="/sitemap.xml"></head></html>'

SITEMAP_SPEC_LEAF_XML = <<~XML
  <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    <url><loc>https://example.com/post-1</loc><priority>0.8</priority></url>
  </urlset>
XML

SITEMAP_SPEC_INDEX_XML = <<~XML
  <?xml version="1.0" encoding="UTF-8"?>
  <sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    <sitemap><loc>https://example.com/post-sitemap.xml</loc></sitemap>
    <sitemap><loc>https://example.com/page-sitemap.xml</loc></sitemap>
  </sitemapindex>
XML

SITEMAP_SPEC_FIVE_SUB_INDEX_XML = begin
  locs = (1..5).map { |i| "<sitemap><loc>https://example.com/sitemap-#{i}.xml</loc></sitemap>" }.join
  "<?xml version=\"1.0\"?><sitemapindex xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">#{locs}</sitemapindex>"
end

SITEMAP_SPEC_MIXED_PRIORITY_XML = <<~XML
  <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    <url><loc>https://example.com/low</loc><priority>0.29</priority></url>
    <url><loc>https://example.com/edge</loc><priority>0.3</priority></url>
    <url><loc>https://example.com/high</loc><priority>0.8</priority></url>
  </urlset>
XML

RSpec.describe Html2rss::AutoSource::Scraper::Sitemap do
  let(:url) { 'https://example.com/blog' }
  let(:logged) { [] }
  let(:requested) { [] }
  let(:recent) { (Time.now.utc - (29 * 86_400)).iso8601 }
  let(:stale) { (Time.now.utc - (31 * 86_400)).iso8601 }

  before do
    allow(Html2rss::Log).to receive(:warn) { |json| logged << JSON.parse(json) }
  end

  describe '.options_key' do
    it 'returns the sitemap scraper key' do
      expect(described_class.options_key).to eq(:sitemap)
    end
  end

  describe '.request_slots' do
    it 'reserves one discovery request plus MAX_SUB_SITEMAPS fan-out slots' do
      expect(described_class.request_slots).to eq(4)
    end
  end

  describe '.articles?' do
    it 'returns true when link[rel="sitemap"] is present' do
      html = '<html><head><link rel="sitemap" href="/sitemap.xml"></head></html>'
      expect(described_class.articles?(Nokogiri::HTML(html))).to be(true)
    end

    it 'returns true when document is a sitemap XML' do
      xml = '<?xml version="1.0"?><urlset><url><loc>https://example.com/1</loc></url></urlset>'
      expect(described_class.articles?(Nokogiri::HTML(xml))).to be(true)
    end

    it 'returns true when document is a sitemapindex XML' do
      expect(described_class.articles?(Nokogiri::HTML(SITEMAP_SPEC_INDEX_XML))).to be(true)
    end

    it 'returns false when no sitemap markers exist' do
      expect(described_class.articles?(Nokogiri::HTML('<html><body><p>Hello</p></body></html>'))).to be(false)
    end

    it 'returns false for a sitemap link without an href' do
      expect(described_class.articles?(Nokogiri::HTML('<link rel="sitemap">'))).to be(false)
    end

    it 'returns false when there is no parsed body' do
      expect(described_class.articles?(nil)).to be(false)
    end
  end

  describe '#initialize' do
    it 'applies a 0.3 minimum priority by default, keeping the boundary value' do
      xml = SITEMAP_SPEC_MIXED_PRIORITY_XML
      articles = described_class.new(Nokogiri::HTML(xml), url:, body: xml).to_a
      expect(articles.map { _1[:url] }).to eq(['https://example.com/edge', 'https://example.com/high'])
    end

    it 'applies a 30 day maximum age by default' do
      xml = <<~XML
        <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
          <url><loc>https://example.com/fresh</loc><lastmod>#{recent}</lastmod></url>
          <url><loc>https://example.com/old</loc><lastmod>#{stale}</lastmod></url>
        </urlset>
      XML
      articles = described_class.new(Nokogiri::HTML(xml), url:, body: xml).to_a
      expect(articles.map { _1[:url] }).to eq(['https://example.com/fresh'])
    end

    it 'forwards min_priority to the parser' do
      xml = SITEMAP_SPEC_LEAF_XML
      expect(described_class.new(Nokogiri::HTML(xml), url:, body: xml, min_priority: 0.9).to_a).to be_empty
    end

    it 'forwards max_age_days to the parser' do
      xml = <<~XML
        <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
          <url><loc>https://example.com/old</loc><lastmod>#{stale}</lastmod></url>
        </urlset>
      XML
      articles = described_class.new(Nokogiri::HTML(xml), url:, body: xml, max_age_days: 60).to_a
      expect(articles.map { _1[:url] }).to eq(['https://example.com/old'])
    end
  end

  describe '#extractable?' do
    it 'returns true for a page that links a sitemap' do
      expect(described_class.new(Nokogiri::HTML(SITEMAP_SPEC_LINK_HTML), url:).extractable?).to be(true)
    end

    it 'returns false for a page without sitemap markers' do
      expect(described_class.new(Nokogiri::HTML('<p>Hi</p>'), url:).extractable?).to be(false)
    end
  end

  describe '#each' do
    it 'returns an enumerator when no block is given' do
      xml = SITEMAP_SPEC_LEAF_XML
      expect(described_class.new(Nokogiri::HTML(xml), url:, body: xml).each).to be_a(Enumerator)
    end

    it 'yields url, title and published_at for each entry' do
      xml = <<~XML
        <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:news="http://www.google.com/schemas/sitemap-news/0.9">
          <url><loc>https://example.com/a</loc><news:news><news:publication_date>#{recent}</news:publication_date><news:title>Title A</news:title></news:news></url>
        </urlset>
      XML
      articles = described_class.new(Nokogiri::HTML(xml), url:, body: xml).to_a
      published_at = Time.parse(recent).utc.iso8601
      expect(articles).to eq([{ url: 'https://example.com/a', title: 'Title A', published_at: }])
    end

    it 'omits title and published_at keys when the entry lacks them' do
      xml = '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"><url><loc>https://example.com/bare</loc></url></urlset>'
      articles = described_class.new(Nokogiri::HTML(xml), url:, body: xml).to_a
      expect(articles).to eq([{ url: 'https://example.com/bare' }])
    end

    it 'yields nothing for an empty urlset' do
      xml = '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"></urlset>'
      expect(described_class.new(Nokogiri::HTML(xml), url:, body: xml).to_a).to eq([])
    end
  end

  describe '#fetch_and_parse_entries' do
    it 'parses a direct sitemap body without requesting anything' do
      xml = SITEMAP_SPEC_LEAF_XML
      session = instance_double(Html2rss::RequestSession)
      expect(described_class.new(Nokogiri::HTML(xml), url:, body: xml, request_session: session).to_a.size).to eq(1)
    end

    it 'stops and logs when the initial fetch exhausts the request budget', :aggregate_failures do
      session = instance_double(Html2rss::RequestSession)
      allow(session).to receive(:follow_up).and_raise(Html2rss::RequestService::RequestBudgetExceeded)

      articles = described_class.new(Nokogiri::HTML(SITEMAP_SPEC_LINK_HTML), url:, request_session: session).to_a
      expect(articles).to eq([])
      expect(logged).to eq([{ 'event_name' => 'sitemap.budget_exhausted', 'host' => 'example.com',
                              'message' => "#{described_class}: sitemap fetch stopped — request budget exhausted" }])
    end

    it 'yields nothing when there is neither a direct body nor a request session' do
      expect(described_class.new(Nokogiri::HTML(SITEMAP_SPEC_LINK_HTML), url:).to_a).to eq([])
    end

    it 'yields nothing when the fetched sitemap has no entries' do
      session = instance_double(Html2rss::RequestSession)
      allow(session).to receive(:follow_up).and_return(mock_sitemap_response('<urlset/>'))
      expect(described_class.new(Nokogiri::HTML(SITEMAP_SPEC_LINK_HTML), url:, request_session: session).to_a).to eq([])
    end
  end

  describe '#fetch_xml' do
    it 'yields nothing when the follow-up response is missing' do
      session = instance_double(Html2rss::RequestSession)
      allow(session).to receive(:follow_up).and_return(nil)
      expect(described_class.new(Nokogiri::HTML(SITEMAP_SPEC_LINK_HTML), url:, request_session: session).to_a).to eq([])
    end

    it 'logs and yields nothing when the fetch raises an Html2rss error', :aggregate_failures do
      session = instance_double(Html2rss::RequestSession)
      allow(session).to receive(:follow_up).and_raise(Html2rss::Error, 'boom')

      articles = described_class.new(Nokogiri::HTML(SITEMAP_SPEC_LINK_HTML), url:, request_session: session).to_a
      expect(articles).to eq([])
      expect(logged).to eq([{ 'event_name' => 'sitemap.fetch_failed', 'host' => 'example.com',
                              'error_class' => 'Html2rss::Error',
                              'message' => "#{described_class}: failed to fetch sitemap (Html2rss::Error: boom)" }])
    end
  end

  describe '#target_sitemap_url' do
    it 'defaults to /sitemap.xml on the page origin when no link tag exists' do
      session = mock_session(SITEMAP_SPEC_LEAF_XML)
      described_class.new(Nokogiri::HTML('<html><body></body></html>'), url:, request_session: session).to_a
      expect(session).to have_received(:follow_up)
        .with(hash_including(url: an_object_having_attributes(to_s: 'https://example.com/sitemap.xml')))
    end

    it 'uses the href of the sitemap link tag' do
      session = mock_session(SITEMAP_SPEC_LEAF_XML)
      html = '<link rel="sitemap" href="/news/sitemap.xml">'
      described_class.new(Nokogiri::HTML(html), url:, request_session: session).to_a
      expect(session).to have_received(:follow_up)
        .with(hash_including(url: an_object_having_attributes(to_s: 'https://example.com/news/sitemap.xml')))
    end

    it 'resolves a relative link href against the page url' do
      session = mock_session(SITEMAP_SPEC_LEAF_XML)
      html = '<link rel="sitemap" href="sitemaps/posts.xml">'
      described_class.new(Nokogiri::HTML(html), url:, request_session: session).to_a
      expect(session).to have_received(:follow_up)
        .with(hash_including(url: an_object_having_attributes(to_s: 'https://example.com/sitemaps/posts.xml')))
    end

    it 'keeps an absolute link href as-is' do
      session = mock_session(SITEMAP_SPEC_LEAF_XML)
      html = '<link rel="sitemap" href="https://cdn.example.com/map.xml">'
      described_class.new(Nokogiri::HTML(html), url:, request_session: session).to_a
      expect(session).to have_received(:follow_up)
        .with(hash_including(url: an_object_having_attributes(to_s: 'https://cdn.example.com/map.xml')))
    end
  end

  describe '#parse_direct_sitemap' do
    it 'does not parse a body that is not a sitemap document' do
      session = mock_session(SITEMAP_SPEC_LEAF_XML)
      articles = described_class.new(Nokogiri::HTML(SITEMAP_SPEC_LINK_HTML), url:, body: '<p>not a sitemap</p>',
                                                                             request_session: session).to_a
      expect(articles.map { _1[:url] }).to eq(['https://example.com/post-1'])
    end

    it 'requests the sitemap when no body is given, even if the page is itself a sitemap' do
      session = mock_session(SITEMAP_SPEC_LEAF_XML)
      articles = described_class.new(Nokogiri::HTML(SITEMAP_SPEC_LEAF_XML), url:, request_session: session).to_a
      expect(articles.map { _1[:url] }).to eq(['https://example.com/post-1'])
    end
  end

  describe '#parse_sitemap_xml' do
    it 'fans out when the fetched document is a sitemapindex' do
      session = mock_session(SITEMAP_SPEC_INDEX_XML, SITEMAP_SPEC_LEAF_XML, SITEMAP_SPEC_LEAF_XML)
      articles = described_class.new(Nokogiri::HTML(SITEMAP_SPEC_LINK_HTML), url:, request_session: session).to_a
      expect(articles.size).to eq(2)
    end
  end

  describe '#fetch_sub_sitemaps' do
    it 'fetches at most MAX_SUB_SITEMAPS sub-sitemaps' do
      session = mock_session(SITEMAP_SPEC_FIVE_SUB_INDEX_XML, SITEMAP_SPEC_LEAF_XML, SITEMAP_SPEC_LEAF_XML,
                             SITEMAP_SPEC_LEAF_XML)
      described_class.new(Nokogiri::HTML(SITEMAP_SPEC_LINK_HTML), url:, request_session: session).to_a
      expect(session).to have_received(:follow_up).exactly(4).times
    end

    it 'keeps fanning out after a sub-sitemap yields no body' do
      session = mock_session(SITEMAP_SPEC_INDEX_XML, nil, SITEMAP_SPEC_LEAF_XML)
      articles = described_class.new(Nokogiri::HTML(SITEMAP_SPEC_LINK_HTML), url:, request_session: session).to_a
      expect(articles.size).to eq(1)
    end

    it 'stops fan-out at the first sub-sitemap that exhausts the budget', :aggregate_failures do
      session = instance_double(Html2rss::RequestSession)
      allow(session).to receive(:follow_up) do |**kwargs|
        requested << kwargs[:url].to_s
        raise Html2rss::RequestService::RequestBudgetExceeded if requested.size == 3

        mock_sitemap_response(requested.size == 1 ? SITEMAP_SPEC_FIVE_SUB_INDEX_XML : SITEMAP_SPEC_LEAF_XML)
      end

      articles = described_class.new(Nokogiri::HTML(SITEMAP_SPEC_LINK_HTML), url:, request_session: session).to_a
      expect(articles.size).to eq(1)
      expect(requested.size).to eq(3)
    end

    it 'forwards the constructor min_priority to sub-sitemap parsing' do
      session = mock_session(SITEMAP_SPEC_INDEX_XML, SITEMAP_SPEC_LEAF_XML, SITEMAP_SPEC_LEAF_XML)
      articles = described_class.new(Nokogiri::HTML(SITEMAP_SPEC_LINK_HTML), url:, request_session: session,
                                                                             min_priority: 0.9).to_a
      expect(articles).to be_empty
    end

    it 'applies the default min_priority to sub-sitemap entries' do
      low_xml = '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">' \
                '<url><loc>https://example.com/x</loc><priority>0.1</priority></url></urlset>'
      session = mock_session(SITEMAP_SPEC_INDEX_XML, low_xml, low_xml)
      expect(described_class.new(Nokogiri::HTML(SITEMAP_SPEC_LINK_HTML), url:, request_session: session).to_a).to eq([])
    end

    it 'applies the max_age_days filter to sub-sitemap entries' do
      stale_xml = '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">' \
                  "<url><loc>https://example.com/old</loc><lastmod>#{stale}</lastmod></url></urlset>"
      session = mock_session(SITEMAP_SPEC_INDEX_XML, stale_xml, stale_xml)
      expect(described_class.new(Nokogiri::HTML(SITEMAP_SPEC_LINK_HTML), url:, request_session: session).to_a).to eq([])
    end
  end

  describe '#fetch_sub_sitemap_entries' do
    it 'logs a fan-out budget event when a sub-sitemap exhausts the budget' do
      session = instance_double(Html2rss::RequestSession)
      allow(session).to receive(:follow_up) do |**kwargs|
        requested << kwargs[:url].to_s
        raise Html2rss::RequestService::RequestBudgetExceeded if requested.size > 1

        mock_sitemap_response(SITEMAP_SPEC_INDEX_XML)
      end

      described_class.new(Nokogiri::HTML(SITEMAP_SPEC_LINK_HTML), url:, request_session: session).to_a
      expect(logged).to eq([{ 'event_name' => 'sitemap.fanout_budget_exhausted', 'host' => 'example.com',
                              'message' => "#{described_class}: sitemap fan-out stopped — request budget exhausted" }])
    end
  end
end
# rubocop:enable RSpec/ExampleLength
