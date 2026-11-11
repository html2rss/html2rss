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
    # A URL rendered several times keeps its strongest placement. PageLinks owns no keep
    # or drop rule; {Corroboration} reads it.
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
        @index = document&.index
        @link_resolver = link_resolver
        walk(document.root, false) if document
        @sparse = document.nil? || document.degraded || content_link_count <= SPARSE_MAX_CONTENT_LINKS
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
      # The rendered content anchor's URL for the article +url+ names, so an item
      # carrying a +http+ or tracked variant can take the page's canonical form.
      #
      # @param url [Html2rss::Url, nil] candidate item URL
      # @return [Html2rss::Url, nil] nil unless +url+ is placed as +:content+
      def canonical_url(url) = @hrefs[url&.article_identity]

      ##
      # True when absence cannot be told from an unrendered list: no page, a degraded SST,
      # or at most {SPARSE_MAX_CONTENT_LINKS} distinct content URLs.
      #
      # @return [Boolean]
      def sparse? = @sparse

      private

      def walk(node, peripheral)
        peripheral ||= node.utility_landmark?
        record(node, peripheral) if node.link?
        node.children.each { walk(_1, peripheral) }
      end

      def record(anchor, peripheral)
        url = @link_resolver.destination_facts(anchor)&.url
        return unless url

        key = url.article_identity
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
