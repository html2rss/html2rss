# frozen_string_literal: true

module Html2rss
  class AutoSource
    class PageLinks
      ##
      # The card units of one SST subtree: its largest one-card subtrees ({Html::CardWalk.crowded?}: one
      # destination, at most one heading) that hold a destination and are rooted outside a heading (a
      # heading holding a link is a headline, not a card). Headings outside every card unit are stray.
      # Bare +div+ cards count like +article+ or +li+ ones: the unit is read from structure, not tag names.
      class CardUnits
        Unit = Data.define(:keys, :headings, :cards, :stray)
        ##
        # Destinations and headings of one subtree, and the card units and stray headings its children hold.
        class Unit
          # The empty unit (a left-out subtree).
          NONE = new(keys: [].freeze, headings: 0, cards: 0, stray: 0)

          # @return [Boolean] whether the unit holds more than one card
          def crowded? = Html::CardWalk.crowded?(heading_count: headings, distinct_main_hrefs: keys.size)
        end
        private_constant :Unit

        ##
        # @param root [SST::Node] subtree to read
        # @param skip [SST::Node, nil] a subtree left out (a section's own label)
        # @param claims [AnchorClaims] resolves an anchor's destination
        def initialize(root, skip:, claims:)
          @skip = skip
          @claims = claims
          @unit = survey(root)
          freeze
        end

        # @return [Integer] card units below the root
        def cards = @unit.cards

        # @return [Integer] headings below the root outside every card unit
        def stray = @unit.stray

        private

        def survey(node)
          return Unit::NONE if node.equal?(@skip)

          units = node.children.map { survey(_1) }
          cards, stray = split(node.children, units)
          Unit.new(keys: keys(node, units), headings: headings(node, units), cards:, stray:)
        end

        def keys(node, units)
          keys = units.flat_map(&:keys)
          keys << @claims.key_of(node) if node.link?
          keys.compact.uniq
        end

        def headings(node, units) = units.sum(&:headings) + (node.heading? ? 1 : 0)

        def split(children, units)
          children.zip(units).reduce([0, 0]) do |(cards, stray), (child, unit)|
            next [cards + unit.cards, stray + unit.stray] if unit.crowded?
            next [cards + 1, stray] if unit.keys.any? && !child.heading?

            [cards, stray + unit.headings]
          end
        end
      end
      private_constant :CardUnits
    end
  end
end
