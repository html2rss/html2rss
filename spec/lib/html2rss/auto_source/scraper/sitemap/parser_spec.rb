# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable RSpec/ExampleLength
PARSER_SPEC_URLSET = lambda do |body|
  '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" ' \
    "xmlns:news=\"http://www.google.com/schemas/sitemap-news/0.9\">#{body}</urlset>"
end

PARSER_SPEC_ENTRY = ->(loc, extra = '') { "<url><loc>#{loc}</loc>#{extra}</url>" }

RSpec.describe Html2rss::AutoSource::Scraper::Sitemap::Parser do
  let(:now) { Time.now.utc.round }
  let(:recent) { (now - 86_400).iso8601 }
  let(:stale) { (now - (31 * 86_400)).iso8601 }

  describe '.call' do
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

      it 'forwards max_age_days to the parser' do
        xml = PARSER_SPEC_URLSET.call(PARSER_SPEC_ENTRY.call('https://example.com/old', "<lastmod>#{stale}</lastmod>"))
        expect(described_class.call(xml, max_age_days: 60).entries.map(&:url)).to eq(['https://example.com/old'])
      end

      it 'parses a urlset that has no namespace' do
        xml = '<urlset><url><loc>https://example.com/a</loc></url></urlset>'
        expect(described_class.call(xml).entries.map(&:url)).to eq(['https://example.com/a'])
      end

      it 'parses a sitemapindex that has no namespace' do
        xml = '<sitemapindex><sitemap><loc>https://example.com/s.xml</loc></sitemap></sitemapindex>'
        expect(described_class.call(xml).sub_sitemap_urls).to eq(['https://example.com/s.xml'])
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

  describe '#initialize' do
    it 'uses a 0.3 minimum priority and a 30 day maximum age by default' do
      xml = PARSER_SPEC_URLSET.call(
        PARSER_SPEC_ENTRY.call('https://example.com/low', '<priority>0.2</priority>') +
        PARSER_SPEC_ENTRY.call('https://example.com/edge', '<priority>0.3</priority>') +
        PARSER_SPEC_ENTRY.call('https://example.com/stale', "<lastmod>#{stale}</lastmod>")
      )
      expect(described_class.new(xml).call.entries.map(&:url)).to eq(['https://example.com/edge'])
    end

    it 'stores the supplied minimum priority' do
      xml = PARSER_SPEC_URLSET.call(PARSER_SPEC_ENTRY.call('https://example.com/a', '<priority>0.8</priority>'))
      expect(described_class.new(xml, min_priority: 0.9).call.entries).to be_empty
    end

    it 'stores the supplied maximum age' do
      xml = PARSER_SPEC_URLSET.call(PARSER_SPEC_ENTRY.call('https://example.com/a', "<lastmod>#{recent}</lastmod>"))
      expect(described_class.new(xml, max_age_days: 0).call.entries).to be_empty
    end
  end

  describe '#invalid_xml?' do
    it 'treats malformed XML that still contains a urlset as parseable' do
      xml = PARSER_SPEC_URLSET.call('<url><loc>https://example.com/a</loc></url><url><loc>https://example.com/b</loc>')
      expect(described_class.call(xml).entries.map(&:url)).to include('https://example.com/a')
    end

    it 'treats malformed XML without a urlset or sitemapindex as invalid' do
      xml = '<root><url><loc>https://example.com/a</loc></url>'
      expect(described_class.call(xml).entries).to be_empty
    end
  end

  describe '#extract_sub_sitemap_urls' do
    it 'strips whitespace from sub-sitemap locations' do
      xml = '<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">' \
            "<sitemap><loc>  https://example.com/a.xml \n</loc></sitemap></sitemapindex>"
      expect(described_class.call(xml).sub_sitemap_urls).to eq(['https://example.com/a.xml'])
    end

    it 'ignores sub-sitemaps with blank locations' do
      xml = '<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">' \
            '<sitemap><loc>   </loc></sitemap><sitemap><loc>https://example.com/b.xml</loc></sitemap></sitemapindex>'
      expect(described_class.call(xml).sub_sitemap_urls).to eq(['https://example.com/b.xml'])
    end
  end

  describe '#build_entry' do
    it 'skips entries without a loc' do
      xml = PARSER_SPEC_URLSET.call('<url><priority>0.9</priority></url>')
      expect(described_class.call(xml).entries).to be_empty
    end

    it 'skips entries whose loc is blank' do
      expect(described_class.call(PARSER_SPEC_URLSET.call(PARSER_SPEC_ENTRY.call('   '))).entries).to be_empty
    end

    it 'excludes entries below the minimum priority' do
      xml = PARSER_SPEC_URLSET.call(PARSER_SPEC_ENTRY.call('https://example.com/a', '<priority>0.2</priority>'))
      expect(described_class.call(xml).entries).to be_empty
    end

    it 'keeps entries that have no date' do
      xml = PARSER_SPEC_URLSET.call(PARSER_SPEC_ENTRY.call('https://example.com/a'))
      expect(described_class.call(xml, max_age_days: 0).entries.map(&:url)).to eq(['https://example.com/a'])
    end
  end

  describe '#build_entry_facts' do
    it 'builds an entry with url, title, date, priority and changefreq' do
      xml = PARSER_SPEC_URLSET.call(
        '<url><loc>https://example.com/a</loc>' \
        "<lastmod>#{recent}</lastmod><changefreq>daily</changefreq><priority>0.8</priority>" \
        '<news:news><news:title>T</news:title></news:news></url>'
      )
      expect(described_class.call(xml).entries.first).to have_attributes(
        url: 'https://example.com/a', title: 'T', published_at: Time.parse(recent).utc.iso8601,
        priority: 0.8, changefreq: 'daily'
      )
    end
  end

  describe '#parse_loc' do
    it 'strips whitespace around the loc value' do
      xml = PARSER_SPEC_URLSET.call(PARSER_SPEC_ENTRY.call('  https://example.com/a  '))
      expect(described_class.call(xml).entries.first.url).to eq('https://example.com/a')
    end
  end

  describe '#parse_title' do
    it 'strips whitespace from the news title' do
      xml = PARSER_SPEC_URLSET.call(
        '<url><loc>https://example.com/a</loc><news:news><news:title>  Hello  </news:title></news:news></url>'
      )
      expect(described_class.call(xml).entries.first.title).to eq('Hello')
    end

    it 'leaves the title nil when no news title is present' do
      xml = PARSER_SPEC_URLSET.call(PARSER_SPEC_ENTRY.call('https://example.com/a'))
      expect(described_class.call(xml).entries.first.title).to be_nil
    end
  end

  describe '#parse_priority' do
    it 'reads the priority value' do
      xml = PARSER_SPEC_URLSET.call(PARSER_SPEC_ENTRY.call('https://example.com/a', '<priority>0.7</priority>'))
      expect(described_class.call(xml).entries.first.priority).to eq(0.7)
    end

    it 'trims whitespace around the priority value' do
      xml = PARSER_SPEC_URLSET.call(PARSER_SPEC_ENTRY.call('https://example.com/a', '<priority> 0.7 </priority>'))
      expect(described_class.call(xml).entries.first.priority).to eq(0.7)
    end

    it 'defaults to 0.5 when no priority is given' do
      xml = PARSER_SPEC_URLSET.call(PARSER_SPEC_ENTRY.call('https://example.com/a'))
      expect(described_class.call(xml, min_priority: 0.0).entries.first.priority).to eq(0.5)
    end
  end

  describe '#parse_changefreq' do
    it 'downcases and trims the changefreq value' do
      xml = PARSER_SPEC_URLSET.call(PARSER_SPEC_ENTRY.call('https://example.com/a', '<changefreq> Daily </changefreq>'))
      expect(described_class.call(xml).entries.first.changefreq).to eq('daily')
    end

    it 'excludes entries marked NEVER in any letter case' do
      xml = PARSER_SPEC_URLSET.call(
        PARSER_SPEC_ENTRY.call('https://example.com/a', '<priority>0.9</priority><changefreq>NEVER</changefreq>')
      )
      expect(described_class.call(xml).entries).to be_empty
    end

    it 'leaves changefreq nil when absent' do
      xml = PARSER_SPEC_URLSET.call(PARSER_SPEC_ENTRY.call('https://example.com/a'))
      expect(described_class.call(xml).entries.first.changefreq).to be_nil
    end
  end

  describe '#raw_date_from' do
    it 'prefers the news publication date over lastmod' do
      news_date = (now - 3600).iso8601
      xml = PARSER_SPEC_URLSET.call(
        "<url><loc>https://example.com/a</loc><lastmod>#{(now - 7200).iso8601}</lastmod>" \
        "<news:news><news:publication_date>#{news_date}</news:publication_date></news:news></url>"
      )
      expect(described_class.call(xml).entries.first.published_at).to eq(news_date)
    end

    it 'falls back to lastmod when there is no news publication date' do
      xml = PARSER_SPEC_URLSET.call(PARSER_SPEC_ENTRY.call('https://example.com/a', "<lastmod>#{recent}</lastmod>"))
      expect(described_class.call(xml).entries.first.published_at).to eq(Time.parse(recent).utc.iso8601)
    end
  end

  describe '#parse_date' do
    it 'normalizes dates to UTC ISO 8601' do
      offset_date = (now - 3600).getlocal('+02:00').iso8601
      entry = PARSER_SPEC_ENTRY.call('https://example.com/a', "<lastmod>#{offset_date}</lastmod>")
      parsed = described_class.call(PARSER_SPEC_URLSET.call(entry)).entries.first
      expect(parsed.published_at).to eq((now - 3600).iso8601)
    end

    it 'omits the date for unparseable values but keeps the entry' do
      entry = PARSER_SPEC_ENTRY.call('https://example.com/a', '<lastmod>not a date</lastmod>')
      expect(described_class.call(PARSER_SPEC_URLSET.call(entry)).entries.first)
        .to have_attributes(url: 'https://example.com/a', published_at: nil)
    end
  end

  describe '#stale_date?' do
    it 'measures max_age_days in days' do
      half_day = (now - 43_200).iso8601
      two_days = (now - (2 * 86_400)).iso8601
      xml = PARSER_SPEC_URLSET.call(
        PARSER_SPEC_ENTRY.call('https://example.com/a', "<lastmod>#{half_day}</lastmod>") +
        PARSER_SPEC_ENTRY.call('https://example.com/b', "<lastmod>#{two_days}</lastmod>")
      )
      expect(described_class.call(xml, max_age_days: 1).entries.map(&:url)).to eq(['https://example.com/a'])
    end

    it 'excludes entries older than max_age_days' do
      xml = PARSER_SPEC_URLSET.call(PARSER_SPEC_ENTRY.call('https://example.com/a', "<lastmod>#{stale}</lastmod>"))
      expect(described_class.call(xml).entries).to be_empty
    end
  end
end
# rubocop:enable RSpec/ExampleLength
