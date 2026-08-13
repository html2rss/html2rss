# frozen_string_literal: true

require 'date'
require 'nokogiri'

module Html2rss
  class AutoSource
    module Scraper
      class Sitemap
        ##
        # Parses XML sitemap documents and extracts prioritized, recent article entries.
        class Parser
          # Default minimum priority threshold (0.0 to 1.0)
          DEFAULT_MIN_PRIORITY = 0.3
          # Default maximum age in days for sitemap entries
          DEFAULT_MAX_AGE_DAYS = 30
          # Google News sitemap XML namespace
          NEWS_NS = 'http://www.google.com/schemas/sitemap-news/0.9'

          # Result value object returned by .call
          # @!attribute entries [Array<SitemapEntry>] parsed entries (empty for sitemapindex docs)
          # @!attribute sub_sitemap_urls [Array<String>] child sitemap URLs (empty for urlset docs)
          Result = Data.define(:entries, :sub_sitemap_urls)

          # Immutable facts for one sitemap entry
          SitemapEntry = Data.define(:url, :title, :published_at, :priority, :changefreq)

          class << self
            ##
            # Parses sitemap XML body and returns a Result.
            #
            # @param xml_content [String] sitemap XML body string
            # @param min_priority [Float] minimum priority score (0.0..1.0)
            # @param max_age_days [Integer] maximum age in days for entries
            # @return [Result] result with entries and/or sub_sitemap_urls
            def call(xml_content, min_priority: DEFAULT_MIN_PRIORITY, max_age_days: DEFAULT_MAX_AGE_DAYS)
              new(xml_content, min_priority:, max_age_days:).call
            end
          end

          ##
          # @param xml_content [String]
          # @param min_priority [Float]
          # @param max_age_days [Integer]
          def initialize(xml_content, min_priority: DEFAULT_MIN_PRIORITY, max_age_days: DEFAULT_MAX_AGE_DAYS)
            @xml_content = xml_content
            @min_priority = min_priority
            @max_age_days = max_age_days
          end

          ##
          # @return [Result]
          def call
            document = Nokogiri::XML(xml_content)
            return Result.new(entries: [], sub_sitemap_urls: []) if invalid_xml?(document)

            if sitemapindex?(document)
              Result.new(entries: [], sub_sitemap_urls: extract_sub_sitemap_urls(document))
            else
              Result.new(entries: extract_entries(document), sub_sitemap_urls: [])
            end
          end

          private

          attr_reader :xml_content, :min_priority, :max_age_days

          def invalid_xml?(document)
            document.errors.any? && document.at_css('urlset, sitemapindex').nil?
          end

          def sitemapindex?(document)
            !document.at_xpath('//*[local-name()="sitemapindex"]').nil?
          end

          def extract_sub_sitemap_urls(document)
            document.xpath('//*[local-name()="sitemap"]/*[local-name()="loc"]').filter_map do |node|
              text = node.text.strip
              text unless text.empty?
            end
          end

          def extract_entries(document)
            document.xpath('//*[local-name()="url"]').filter_map { build_entry(_1) }
          end

          def build_entry(url_node)
            loc = parse_loc(url_node)
            return unless loc
            return if invalid_entry_signals?(url_node)

            published_at = parse_date(url_node)
            return if stale_date?(published_at)

            build_entry_facts(url_node, loc, published_at)
          end

          def build_entry_facts(url_node, loc, published_at)
            SitemapEntry.new(
              url: loc,
              title: parse_title(url_node),
              published_at:,
              priority: parse_priority(url_node),
              changefreq: parse_changefreq(url_node)
            )
          end

          def parse_loc(url_node)
            node = url_node.at_xpath('./*[local-name()="loc"]')
            text = node&.text&.strip
            text unless text.to_s.empty?
          end

          def parse_changefreq(url_node)
            node = url_node.at_xpath('./*[local-name()="changefreq"]')
            node ? node.text.strip.downcase : nil
          end

          def invalid_entry_signals?(url_node)
            parse_priority(url_node) < min_priority || parse_changefreq(url_node) == 'never'
          end

          def parse_priority(url_node)
            node = url_node.at_xpath('./*[local-name()="priority"]')
            text = node&.text&.strip
            text ? text.to_f : 0.5
          end

          def parse_date(url_node)
            raw_date = raw_date_from(url_node)
            return unless raw_date

            Time.parse(raw_date).utc.iso8601
          rescue ArgumentError
            nil
          end

          def raw_date_from(url_node)
            news_node = url_node.at_xpath('.//news:publication_date', 'news' => NEWS_NS)
            lastmod_node = url_node.at_xpath('./*[local-name()="lastmod"]')
            (news_node || lastmod_node)&.text&.strip
          end

          def parse_title(url_node)
            node = url_node.at_xpath('.//news:title', 'news' => NEWS_NS)
            node&.text&.strip
          end

          def stale_date?(published_at)
            return false unless published_at

            time = Time.parse(published_at)
            (Time.now.utc - time) > (max_age_days * 86_400)
          rescue ArgumentError
            false
          end
        end
      end
    end
  end
end
