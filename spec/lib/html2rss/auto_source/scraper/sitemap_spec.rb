# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::AutoSource::Scraper::Sitemap do
  let(:url) { 'https://example.com/blog' }

  let(:leaf_sitemap_xml) do
    <<~XML
      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        <url><loc>https://example.com/post-1</loc><priority>0.8</priority></url>
      </urlset>
    XML
  end

  let(:index_sitemap_xml) do
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        <sitemap><loc>https://example.com/post-sitemap.xml</loc></sitemap>
        <sitemap><loc>https://example.com/page-sitemap.xml</loc></sitemap>
      </sitemapindex>
    XML
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

    it 'returns false when no sitemap markers exist' do
      expect(described_class.articles?(Nokogiri::HTML('<html><body><p>Hello</p></body></html>'))).to be(false)
    end
  end

  describe '#each' do
    let(:link_html) { '<html><head><link rel="sitemap" href="/sitemap.xml"></head></html>' }

    it 'yields articles parsed from direct XML body', :aggregate_failures do
      articles = described_class.new(Nokogiri::HTML(leaf_sitemap_xml), url:, body: leaf_sitemap_xml).to_a
      expect(articles.size).to eq(1)
      expect(articles.first[:url]).to eq('https://example.com/post-1')
    end

    it 'fetches /sitemap.xml via request_session when link tag is present', :aggregate_failures do
      resp = instance_double(Html2rss::RequestService::Response, body: leaf_sitemap_xml)
      session = instance_double(Html2rss::RequestSession, follow_up: resp)
      articles = described_class.new(Nokogiri::HTML(link_html), url:, request_session: session).to_a
      expect(articles.first[:url]).to eq('https://example.com/post-1')
    end

    context 'when the fetched sitemap is a sitemapindex (fan-out)' do
      it 'fans out to sub-sitemaps and yields entries from the leaves', :aggregate_failures do
        session = mock_session(index_sitemap_xml, leaf_sitemap_xml, leaf_sitemap_xml)
        articles = described_class.new(Nokogiri::HTML(link_html), url:, request_session: session).to_a
        expect(articles.map { _1[:url] }).to eq(['https://example.com/post-1', 'https://example.com/post-1'])
      end
    end

    context 'when fan-out is truncated by MAX_SUB_SITEMAPS' do
      def large_index_xml
        locs = (1..5).map { |i| "<sitemap><loc>https://example.com/sitemap-#{i}.xml</loc></sitemap>" }.join
        "<?xml version=\"1.0\"?><sitemapindex xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">#{locs}</sitemapindex>"
      end

      it 'fetches at most MAX_SUB_SITEMAPS sub-sitemaps' do
        session = mock_session(large_index_xml, leaf_sitemap_xml, leaf_sitemap_xml, leaf_sitemap_xml)
        described_class.new(Nokogiri::HTML(link_html), url:, request_session: session).to_a
        expect(session).to have_received(:follow_up).exactly(4).times
      end
    end

    context 'when a sub-sitemap fetch raises RequestBudgetExceeded' do
      it 'stops fan-out gracefully without raising' do
        session = instance_double(Html2rss::RequestSession)
        allow(session).to receive(:follow_up).ordered.and_return(mock_sitemap_response(index_sitemap_xml))
        allow(session).to receive(:follow_up).ordered.and_raise(Html2rss::RequestService::RequestBudgetExceeded)

        expect { described_class.new(Nokogiri::HTML(link_html), url:, request_session: session).to_a }
          .not_to raise_error
      end
    end

    def mock_session(*xml_bodies)
      session = instance_double(Html2rss::RequestSession)
      responses = xml_bodies.map { |xml| instance_double(Html2rss::RequestService::Response, body: xml) }
      allow(session).to receive(:follow_up).and_return(*responses)
      session
    end

    def mock_sitemap_response(xml)
      instance_double(Html2rss::RequestService::Response, body: xml)
    end
  end
end
