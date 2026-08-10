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
      articles = described_class.new(Nokogiri::HTML(leaf_sitemap_xml), url:).to_a
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
        leaf_resp = instance_double(Html2rss::RequestService::Response, body: leaf_sitemap_xml)
        index_resp = instance_double(Html2rss::RequestService::Response, body: index_sitemap_xml)
        session = instance_double(Html2rss::RequestSession)

        # First call returns the index, subsequent calls return the leaf
        allow(session).to receive(:follow_up).and_return(index_resp, leaf_resp, leaf_resp)

        articles = described_class.new(Nokogiri::HTML(link_html), url:, request_session: session).to_a
        # index has 2 sub-sitemaps, each has 1 entry → 2 total
        expect(articles.size).to eq(2)
        expect(articles.map { _1[:url] }).to all(eq('https://example.com/post-1'))
      end
    end

    context 'when fan-out is truncated by MAX_SUB_SITEMAPS' do
      let(:large_index_xml) do
        locs = (1..5).map { |i| "<sitemap><loc>https://example.com/sitemap-#{i}.xml</loc></sitemap>" }.join
        "<?xml version=\"1.0\"?><sitemapindex xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">#{locs}</sitemapindex>"
      end

      it 'fetches at most MAX_SUB_SITEMAPS sub-sitemaps' do
        index_resp = instance_double(Html2rss::RequestService::Response, body: large_index_xml)
        leaf_resp = instance_double(Html2rss::RequestService::Response, body: leaf_sitemap_xml)
        session = instance_double(Html2rss::RequestSession)

        allow(session).to receive(:follow_up).and_return(index_resp, leaf_resp, leaf_resp, leaf_resp)

        described_class.new(Nokogiri::HTML(link_html), url:, request_session: session).to_a
        # index fetch + MAX_SUB_SITEMAPS (3) leaf fetches = 4 total
        expect(session).to have_received(:follow_up).exactly(4).times
      end
    end

    context 'when a sub-sitemap fetch raises RequestBudgetExceeded' do
      it 'stops fan-out gracefully without raising' do
        index_resp = instance_double(Html2rss::RequestService::Response, body: index_sitemap_xml)
        session = instance_double(Html2rss::RequestSession)

        allow(session).to receive(:follow_up).ordered.and_return(index_resp)
        allow(session).to receive(:follow_up).ordered.and_raise(Html2rss::RequestService::RequestBudgetExceeded)

        expect do
          described_class.new(Nokogiri::HTML(link_html), url:, request_session: session).to_a
        end.not_to raise_error
      end
    end
  end
end
