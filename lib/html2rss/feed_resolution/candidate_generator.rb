# frozen_string_literal: true

module Html2rss
  module FeedResolution
    ##
    # Builds same-origin entry-resolution candidates: one feed slot plus listing seeds.
    #
    # Mix is 1 feed + up to +listing_cap+ listing URLs (nav → segment first-wins →
    # {Syndication::CandidateCatalog::LISTING_PATHS}). Feed never pads into listing slots.
    class CandidateGenerator
      # Max candidates returned to the probe stage.
      DEFAULT_MAX = 5
      # Nav/header/footer anchor sources for DestinationFacts ranking.
      NAV_SELECTORS = 'header a[href], nav a[href], footer a[href]'
      # Segment strategies tried first-wins (≥2 same-origin primary links).
      SEGMENT_STRATEGIES = %i[list cluster semantic].freeze

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
        [feed_slot, *listing_urls.first(listing_cap)].compact.uniq
      end

      private

      attr_reader :entry_url, :response, :max

      def listing_cap = max > 1 ? max - 1 : 0

      def feed_slot
        return unless parsed_html

        url = Syndication::Discovery.candidate_urls(page_url: entry_url, parsed_body: parsed_html).first
        return unless url
        return unless eligible_url?(url)

        url
      end

      def listing_urls
        (nav_candidates + segment_seed_urls + listing_path_candidates)
          .uniq
          .select { eligible_url?(_1) }
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
        rank += 3 if facts.taxonomy_path
        rank += 1 if facts.content_path
        [url, rank] if rank.positive?
      end

      def segment_seed_urls
        return [] unless parsed_html

        sst = SST::Normalizer.call(parsed_html)
        link_resolver = Scoring::LinkResolver.new(entry_url)

        SEGMENT_STRATEGIES.each do |strategy|
          urls = segment_urls_for(sst, strategy, link_resolver)
          return urls if urls.size >= 2
        end
        []
      rescue StandardError
        []
      end

      def segment_urls_for(sst, strategy, link_resolver)
        segmenter = AutoSource::Segmenter.new(sst, base_url: entry_url, strategy:, link_resolver:)
        primary = AutoSource::Segmenter::PrimaryLink.new(segmenter)

        segmenter.call.filter_map do |segment|
          link = segment.primary_link || primary.select(segment.root_node)
          absolute_same_origin(link&.attrs&.href)
        end.uniq
      end

      def listing_path_candidates
        Syndication::CandidateCatalog::LISTING_PATHS.filter_map { |path| absolute_same_origin(path) }
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

      def eligible_url?(url)
        !entry_url.same_document?(url) && same_registrable_domain?(url)
      end

      def same_registrable_domain?(url)
        url.domain == entry_url.domain
      end
    end
  end
end
