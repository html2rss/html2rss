# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::AutoSource::Discovery::Sitemap do
  describe '.call' do
    let(:sample_xml) do
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

    it 'extracts prioritized non-stale entries with titles', :aggregate_failures do
      entries = described_class.call(sample_xml)

      expect(entries.size).to eq(1)
      expect(entries.first.url).to eq('https://example.com/article-1')
      expect(entries.first.title).to eq('Google News Title 1')
      expect(entries.first.priority).to eq(0.8)
    end

    it 'filters out entries below min_priority' do
      entries = described_class.call(sample_xml, min_priority: 0.9)

      expect(entries).to be_empty
    end

    it 'returns empty array for invalid XML' do
      expect(described_class.call('not xml')).to be_empty
    end
  end
end
