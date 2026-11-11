# frozen_string_literal: true

module Html2rss
  class AutoSource
    ##
    # Where each URL is rendered on the page, from one pass over the SST anchors.
    #
    # Keys are {Html2rss::Url#article_identity}, so scheme, tracking query params, trailing
    # slashes and fragments do not split a URL; other query params stay significant. Chrome
    # comes from the SST chrome flag ({SST::Normalizer}); utility landmarks that are not chrome
    # (+aside+, +menu+, sectioned +footer+) are peripheral.
    # A URL rendered several times keeps its strongest placement.
    #
    # The same pass scopes each {LinkDestination::Sponsorship} marker to its card: the smallest
    # element holding the marker and at least one anchor. The card's URL is sponsored when all
    # its anchors share one destination; a marker whose card spans several destinations (an ad
    # slot between list items) marks nothing. PageLinks owns no keep or drop rule;
    # {Corroboration} and {Cleanup} read it.
    class PageLinks
      # Placement strength, strongest first; a URL missing from the page is +:absent+.
      RANKS = { content: 0, peripheral: 1, chrome: 2 }.freeze
      # A page with at most this many distinct content URLs is too sparse to corroborate.
      SPARSE_MAX_CONTENT_LINKS = 2

      ##
      # @param document [SST::Document, nil] page SST; nil when there is no rendered page
      # @param link_resolver [Scoring::LinkResolver, nil] page resolver (shared memo with heuristics);
      #   required when +document+ is present
      # @return [PageLinks]
      def self.build(document, link_resolver:)
        new(document, link_resolver)
      end
      private_class_method :new

      # @param document [SST::Document, nil]
      # @param link_resolver [Scoring::LinkResolver, nil]
      def initialize(document, link_resolver)
        @placements = {}
        @hrefs = {}
        @card_keys = []
        @sponsored = Set.new
        @index = document&.index
        @link_resolver = link_resolver
        walk(document.root, false) if document
        @sparse = document.nil? || document.degraded || content_link_count <= SPARSE_MAX_CONTENT_LINKS
        @card_keys = nil
        freeze
      end

      ##
      # @param url [Html2rss::Url, nil] candidate item URL
      # @return [Symbol] +:content+, +:peripheral+, +:chrome+, or +:absent+
      def placement(url)
        return :absent unless url

        @placements.fetch(url.article_identity, :absent)
      end

      ##
      # The rendered content anchor's URL for the article +url+ names, minus tracking params,
      # so a tracked or +http+ variant takes one stable form (the feed item guid keys on it).
      # An +https+ item never drops to an +http+ anchor.
      #
      # @param url [Html2rss::Url, nil] candidate item URL
      # @return [Html2rss::Url, nil] nil unless +url+ is placed as +:content+
      def canonical_url(url)
        anchor = @hrefs[url&.article_identity]&.without_tracking_params
        return anchor unless anchor && url.scheme == 'https'

        anchor.with_scheme('https')
      end

      ##
      # True when absence cannot be told from an unrendered list: no page, a degraded SST,
      # or at most {SPARSE_MAX_CONTENT_LINKS} distinct content URLs.
      #
      # @return [Boolean]
      def sparse? = @sparse

      ##
      # True when +url+ is rendered inside a card carrying a sponsorship marker.
      #
      # @param url [Html2rss::Url, nil] candidate item URL
      # @return [Boolean]
      def sponsored?(url)
        return false unless url

        @sponsored.include?(url.article_identity)
      end

      private

      # Returns true while a marker in +node+'s subtree still waits for its card.
      def walk(node, peripheral)
        peripheral ||= node.utility_landmark?
        start = @card_keys.size
        record(node, peripheral) if node.link?
        pending = node.children.reduce(LinkDestination::Sponsorship.marker?(node)) do |marked, child|
          walk(child, peripheral) | marked
        end
        pending && !settle_card(start)
      end

      # The subtree's anchors from +start+ form the marker's card once it holds any.
      def settle_card(start)
        keys = @card_keys.drop(start).uniq
        return false if keys.empty?

        @sponsored << keys.first if keys.one?
        true
      end

      def record(anchor, peripheral)
        url = @link_resolver.destination_facts(anchor)&.url
        return unless url

        key = url.article_identity
        @card_keys << key
        placement = anchor_placement(anchor, peripheral)
        current = @placements[key]
        return unless current.nil? || RANKS.fetch(placement) < RANKS.fetch(current)

        @placements[key] = placement
        @hrefs[key] = url if placement == :content
      end

      def anchor_placement(anchor, peripheral)
        return :chrome if @index.ignored_chrome?(anchor)

        peripheral ? :peripheral : :content
      end

      def content_link_count
        @placements.count { |_key, placement| placement == :content }
      end
    end
  end
end
