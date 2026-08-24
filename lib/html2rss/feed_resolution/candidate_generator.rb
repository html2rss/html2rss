# frozen_string_literal: true

module Html2rss
  module FeedResolution
    ##
    # Builds same-origin entry-resolution candidates (feeds, nav, list links, paths).
    class CandidateGenerator
      # Tournament-only HTML path suffixes (shared with {Syndication::CandidateCatalog}).
      LISTING_PATHS = Syndication::CandidateCatalog::LISTING_PATHS
      # Max candidates returned to the probe stage.
      DEFAULT_MAX = 5
      # Nav/header/footer anchor sources for DestinationFacts ranking.
      NAV_SELECTORS = 'header a[href], nav a[href], footer a[href]'

      ##
      # @param entry_url [String, Html2rss::Url]
      # @param response [Html2rss::RequestService::Response]
      # @param max [Integer]
      # @return [Array<Html2rss::Url>]
      def self.call(entry_url:, response:, max: DEFAULT_MAX)
        new(entry_url:, response:, max:).call
      end

      ##
      # @param entry_url [String, Html2rss::Url]
      # @param response [Html2rss::RequestService::Response]
      # @param max [Integer]
      def initialize(entry_url:, response:, max: DEFAULT_MAX)
        @entry_url = Html2rss::Url.from_absolute(entry_url)
        @response = response
        @max = max
      end

      ##
      # @return [Array<Html2rss::Url>]
      def call
        (feed_candidates + nav_candidates + list_link_candidates + listing_path_candidates)
          .uniq
          .reject { |url| same_page?(url) }
          .select { |url| same_registrable_domain?(url) }
          .first(@max)
      end

      private

      attr_reader :entry_url, :response, :max

      def feed_candidates
        return [] unless parsed_html

        Syndication::Discovery.candidate_urls(page_url: entry_url, parsed_body: parsed_html).first(max)
      end

      def nav_candidates
        return [] unless parsed_html

        parsed_html.css(NAV_SELECTORS)
                   .filter_map { |anchor| ranked_anchor_url(anchor) }
                   .sort_by { |(_url, rank)| -rank }
                   .map(&:first)
      end

      def ranked_anchor_url(anchor)
        url = absolute_same_origin(anchor['href'])
        return unless url

        facts = LinkDestination::DestinationFacts.build(url)
        rank = 0
        rank += 2 if facts.content_path
        rank += 1 if facts.taxonomy_path
        [url, rank] if rank.positive?
      end

      def list_link_candidates
        return [] unless response.html_response?

        sst = SST::Normalizer.call(response.body)
        segments = PageRecon.discover_segments(sst, entry_url)
        segments.filter_map { |segment| primary_link_url(segment) }
      rescue StandardError
        []
      end

      def primary_link_url(segment)
        href = segment.primary_link&.attrs&.href
        absolute_same_origin(href)
      rescue StandardError
        nil
      end

      def listing_path_candidates
        LISTING_PATHS.filter_map { |path| absolute_same_origin(path) }
      end

      def parsed_html
        return @parsed_html if defined?(@parsed_html)

        @parsed_html = response.html_response? ? response.parsed_body : nil
      rescue RequestService::UnsupportedResponseContentType
        @parsed_html = nil
      end

      def absolute_same_origin(href)
        return if href.nil? || href.empty? || href.start_with?('#', 'mailto:', 'javascript:')

        Html2rss::Url.from_relative(href, entry_url)
      rescue ArgumentError
        nil
      end

      def same_page?(url)
        url.to_s.chomp('/') == entry_url.to_s.chomp('/')
      end

      def same_registrable_domain?(url)
        url.domain == entry_url.domain
      end
    end
  end
end
