# frozen_string_literal: true

module Html2rss
  class AutoSource
    ##
    # Where each URL is rendered on the page, and which URLs the page marks as sponsored.
    #
    # Keys are {#identity} ({Html2rss::Url#article_identity}), so scheme, tracking query params, trailing
    # slashes and fragments do not split a URL; other query params stay significant, except the page's
    # placement params ({PlacementParams}: a param the page's content links use to place the same story
    # in several slots), which the page's links show and which {#identity} and {#without_placement} drop
    # for every consumer of that key ({Corroboration}, {Cleanup}). Chrome and
    # peripheral both come from the one SST scope rule ({SST::Tags.chrome_scope}, read through
    # {SST::Index#ignored_chrome?} and {SST::Index#peripheral?}): utility landmarks that are not
    # chrome (+aside+, +menu+, role=complementary, in-content +nav+, sectioned +footer+) are peripheral.
    # A URL rendered several times keeps its strongest placement.
    #
    # Each {LinkDestination::Sponsorship} marker is scoped by {SponsoredCards}: a container marks every
    # destination inside it, a linked label its anchor's card unit, a label the dominant destination of
    # the +article+, +section+, +aside+ or +li+ it sits in, and a paid label opening a section every card
    # of that section. PageLinks owns no keep or drop rule; {Corroboration} and {Cleanup} read it.
    #
    # Both facts are walked lazily, once, on first use: a sponsorship check walks markers and
    # resolves only the anchors of marked cards; placement, canonical and sparse checks resolve
    # every anchor.
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
        @document = document
        @link_resolver = link_resolver
        @walks = {}
        freeze
      end

      ##
      # @param url [Html2rss::Url, nil] candidate item URL
      # @return [Symbol] +:content+, +:peripheral+, +:chrome+, or +:absent+
      def placement(url)
        return :absent unless url

        placements.placement(identity(url))
      end

      ##
      # The one article key on this page: {Html2rss::Url#article_identity} less the page's placement params.
      # Every consumer comparing item URLs on this page keys on it, so no two rules decide "same article".
      # A URL without a query has no param to ignore, so it never forces the page walk.
      #
      # @param url [Html2rss::Url]
      # @return [Array] equal for URLs naming the same article on this page
      def identity(url) = url.query ? url.article_identity(ignoring: placements.params) : url.article_identity

      ##
      # +url+ without the page's placement params, so the item guid stays one stable form.
      #
      # @param url [Html2rss::Url]
      # @return [Html2rss::Url] +url+ itself when it carries none
      def without_placement(url) = url.query ? url.without_params(placements.params) : url

      ##
      # The rendered content anchor's URL for the article +url+ names, minus tracking and placement
      # params, so a tracked, placed or +http+ variant takes one stable form (the feed item guid keys on it).
      # An +https+ item never drops to an +http+ anchor.
      #
      # @param url [Html2rss::Url, nil] candidate item URL
      # @return [Html2rss::Url, nil] nil unless +url+ is placed as +:content+
      def canonical_url(url)
        anchor = url && placements.content_url(identity(url))&.without_tracking_params
        anchor &&= without_placement(anchor)
        return anchor unless anchor && url.scheme == 'https'

        anchor.with_scheme('https')
      end

      ##
      # True when absence cannot be told from an unrendered list: no page, a degraded SST,
      # or at most {SPARSE_MAX_CONTENT_LINKS} distinct content URLs.
      #
      # @return [Boolean]
      def sparse? = placements.sparse?

      ##
      # Document position of the first content anchor to the article +url+ names, among the
      # page's distinct content URLs (from the placement walk; no second walk).
      #
      # @param url [Html2rss::Url, nil] candidate item URL
      # @return [Integer, nil] nil unless +url+ is placed as +:content+
      def content_position(url)
        url && content_positions[identity(url)]
      end

      ##
      # True when +url+ is rendered inside a card carrying a sponsorship marker.
      #
      # @param url [Html2rss::Url, nil] candidate item URL
      # @return [Boolean]
      def sponsored?(url)
        return false unless url

        sponsored_cards.include?(identity(url))
      end

      private

      # The +@walks+ memo is the explicit lazy holder: the frozen PageLinks fills each walk once.
      def placements = @walks[:placements] ||= Placements.new(@document, @link_resolver)

      def sponsored_cards
        @walks[:sponsored_cards] ||= SponsoredCards.new(@document, @link_resolver, ->(url) { identity(url) })
      end

      def content_positions = @walks[:content_positions] ||= placements.content_keys.each_with_index.to_h

      ##
      # Strongest placement and content anchor URL per article identity, from one walk that
      # resolves every SST anchor.
      class Placements
        # @param document [SST::Document, nil]
        # @param link_resolver [Scoring::LinkResolver, nil]
        def initialize(document, link_resolver)
          @index = document&.index
          @link_resolver = link_resolver
          links = rendered_links
          @params = PlacementParams.names(links.filter_map { |url, placement| url if placement == :content })
          @by_key = {}
          @content_urls = {}
          links.each { |url, placement| record(url, placement) }
          @sparse = document.nil? || document.degraded || content_link_count <= SPARSE_MAX_CONTENT_LINKS
          freeze
        end

        # @return [Set<String>] the page's placement-only query param names
        attr_reader :params

        # @param key [String] article identity
        # @return [Symbol] placement, or +:absent+
        def placement(key) = @by_key.fetch(key, :absent)

        # @param key [String] article identity
        # @return [Html2rss::Url, nil] the content anchor URL for +key+
        def content_url(key) = @content_urls[key]

        # @return [Boolean]
        def sparse? = @sparse

        # @return [Array<String>] article identities placed as +:content+, in document order
        def content_keys = @content_urls.keys

        private

        # @return [Array<Array(Html2rss::Url, Symbol)>] destination and placement of every anchor, in document order
        def rendered_links
          links = []
          @index&.each_node { links << link_of(_1) if _1.link? }
          links.compact
        end

        def link_of(anchor)
          url = @link_resolver.destination_facts(anchor)&.url
          [url, anchor_placement(anchor)] if url
        end

        def record(url, placement)
          key = url.article_identity(ignoring: @params)
          current = @by_key[key]
          return unless current.nil? || RANKS.fetch(placement) < RANKS.fetch(current)

          @by_key[key] = placement
          @content_urls[key] = url if placement == :content
        end

        def anchor_placement(anchor)
          return :chrome if @index.ignored_chrome?(anchor)

          @index.peripheral?(anchor) ? :peripheral : :content
        end

        def content_link_count = @by_key.count { |_key, placement| placement == :content }
      end
      private_constant :Placements
    end
  end
end
