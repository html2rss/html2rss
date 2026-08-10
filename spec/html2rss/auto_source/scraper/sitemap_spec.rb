# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::AutoSource::Scraper::Sitemap do
  let(:url) { 'https://example.com/blog' }

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
    let(:sitemap_xml) do
      <<~XML
        <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
          <url><loc>https://example.com/post-1</loc><priority>0.8</priority></url>
        </urlset>
      XML
    end
    let(:link_html) { '<html><head><link rel="sitemap" href="/sitemap.xml"></head></html>' }

    it 'yields articles parsed from direct XML body', :aggregate_failures do
      articles = described_class.new(Nokogiri::HTML(sitemap_xml), url:).to_a
      expect(articles.size).to eq(1)
      expect(articles.first[:url]).to eq('https://example.com/post-1')
    end

    it 'fetches /sitemap.xml via request_session when link tag is present', :aggregate_failures do
      resp = instance_double(Html2rss::RequestService::Response, body: sitemap_xml)
      session = instance_double(Html2rss::RequestSession, follow_up: resp)
      articles = described_class.new(Nokogiri::HTML(link_html), url:, request_session: session).to_a
      expect(articles.first[:url]).to eq('https://example.com/post-1')
    end
  end
end
