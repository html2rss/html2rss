# frozen_string_literal: true

module Html2rss
  class AutoSource
    class PageLinks
      ##
      # The anchors of one sponsorship walk, in document order, and which of them sit in a marked scope.
      # Destinations resolve only when a scope asks for them. A claimed destination is sponsored unless
      # some anchor to it stays unclaimed: a promo slot never hides the editorial card linking the story.
      class AnchorClaims
        # @param link_resolver [Scoring::LinkResolver]
        # @param identity [#call] maps a destination URL to its article identity
        def initialize(link_resolver, identity)
          @link_resolver = link_resolver
          @identity = identity
          @anchors = []
          @headline = []
          @claimed = []
          @keys = Set.new
        end

        # @return [Integer] anchors recorded so far; the next anchor's index
        def size = @anchors.size

        ##
        # @param anchor [SST::Node]
        # @param in_heading [Boolean] whether the anchor sits inside a heading
        # @return [Integer] the anchor's index
        def record(anchor, in_heading:)
          @headline << in_heading
          @anchors << anchor
          @anchors.size - 1
        end

        # @param index [Integer]
        # @return [Array, nil] article identity of the anchor's destination
        def key_at(index) = key_of(@anchors.fetch(index))

        # @param anchor [SST::Node]
        # @return [Array, nil] article identity of the anchor's destination
        def key_of(anchor)
          url = @link_resolver.destination_facts(anchor)&.url
          @identity.call(url) if url
        end

        # @param range [Range] anchor indexes
        # @return [Array<Array>] distinct destinations in +range+
        def keys_in(range) = range.filter_map { key_at(_1) }.uniq

        ##
        # The one destination a card in +range+ stands for: its only one, else its only headline one (an
        # anchor in or around a heading).
        #
        # @param range [Range] anchor indexes
        # @return [Array, nil]
        def dominant_key(range)
          keys = keys_in(range)
          return keys.first if keys.one?

          headline_keys = keys_in(range.select { headline?(_1) })
          headline_keys.first if headline_keys.one?
        end

        # Marks +keys+ sponsored and every anchor in +range+ as inside a marked scope.
        #
        # @param range [Range] anchor indexes
        # @param keys [Array<Array>] destinations to mark; every one in +range+ by default
        # @return [void]
        def claim(range, keys = keys_in(range))
          @keys.merge(keys)
          @claimed.fill(true, range)
        end

        # @return [Set<Array>] claimed destinations, less those also linked outside every claimed range
        def sponsored_keys
          @anchors.each_index { @keys.delete(key_at(_1)) unless @claimed[_1] } unless @keys.empty?
          @keys
        end

        private

        def headline?(index) = @headline.fetch(index) || @anchors.fetch(index).children.any? { _1.find(&:heading?) }
      end
      private_constant :AnchorClaims
    end
  end
end
