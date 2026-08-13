# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::AutoSource::Scraper::Sitemap::Parser do
  describe '.call' do
    let(:now_iso) { Time.now.utc.iso8601 }

    let(:urlset_xml) do
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"
                xmlns:news="http://www.google.com/schemas/sitemap-news/0.9">
          <url>
            <loc>https://example.com/article-1</loc>
            <lastmod>#{Time.now.utc.iso8601}</lastmod>
            <changefreq>daily</changefreq>
            <priority>0.8</priority>
            <news:news>
              <news:publication_date>#{Time.now.utc.iso8601}</news:publication_date>
              <news:title>Google News Title 1</news:title>
            </news:news>
          </url>
          <url>
            <loc>https://example.com/utility-page</loc>
            <priority>0.1</priority>
          </url>
          <url>
            <loc>https://example.com/never-change</loc>
            <priority>0.9</priority>
            <changefreq>never</changefreq>
          </url>
        </urlset>
      XML
    end

    let(:sitemapindex_xml) do
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
          <sitemap>
            <loc>https://example.com/post-sitemap.xml</loc>
            <lastmod>2026-08-01</lastmod>
          </sitemap>
          <sitemap>
            <loc>https://example.com/page-sitemap.xml</loc>
          </sitemap>
        </sitemapindex>
      XML
    end

    context 'when given a urlset document' do
      subject(:result) { described_class.call(urlset_xml) }

      it 'returns a Result', :aggregate_failures do
        expect(result).to have_attributes(sub_sitemap_urls: be_empty, entries: have_attributes(size: 1))
        expect(result.entries.first).to have_attributes(
          url: 'https://example.com/article-1', title: 'Google News Title 1', priority: 0.8
        )
      end

      it 'filters out entries below min_priority' do
        expect(described_class.call(urlset_xml, min_priority: 0.9).entries).to be_empty
      end
    end

    context 'when given a sitemapindex document' do
      subject(:result) { described_class.call(sitemapindex_xml) }

      it 'returns a Result with entries empty and sub_sitemap_urls populated', :aggregate_failures do
        expected_urls = ['https://example.com/post-sitemap.xml', 'https://example.com/page-sitemap.xml']
        expect(result).to have_attributes(entries: be_empty, sub_sitemap_urls: expected_urls)
      end
    end

    context 'when given empty XML' do
      subject(:result) { described_class.call('<?xml version="1.0"?><root/>') }

      it 'returns a Result with both collections empty', :aggregate_failures do
        expect(result).to be_a(described_class::Result)
        expect(result.entries).to be_empty
        expect(result.sub_sitemap_urls).to be_empty
      end
    end

    context 'when given invalid XML' do
      subject(:result) { described_class.call('not xml') }

      it 'returns a Result with both collections empty', :aggregate_failures do
        expect(result).to be_a(described_class::Result)
        expect(result.entries).to be_empty
        expect(result.sub_sitemap_urls).to be_empty
      end
    end
  end
end
