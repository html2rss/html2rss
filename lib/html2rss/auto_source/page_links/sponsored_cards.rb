# frozen_string_literal: true

module Html2rss
  class AutoSource
    class PageLinks
      ##
      # Article identities of sponsored cards, from one marker walk ({LinkDestination::Sponsorship.marker}).
      # Anchors are resolved only once a marker binds; a page without markers resolves nothing.
      #
      # Each marker binds in one scope:
      #
      # - A +:container+ marker holding anchors marks every destination inside it.
      # - A marker inside an anchor (a linked label) marks that anchor's destination across its card unit: the
      #   largest unit around the anchor that is still one card ({Html::CardWalk.crowded?}: one destination,
      #   at most one heading), and only when that unit holds a heading.
      # - Any other label (or an anchorless container marker) marks the card it sits in: its nearest
      #   {LinkDestination::Sponsorship::CARD_NAMES} element, itself included. That card marks its dominant
      #   destination: its only one, else its only headline destination (an anchor in or around a heading);
      #   a card with several headlines marks nothing, and so does a label outside every card.
      # - A +:paid_label+ outside every anchor binds at its first ancestor holding a destination after it
      #   (none before it) and climbs no further. When that ancestor is one card unit with a heading, the
      #   label marks that card (a bare +div+ card included). When it holds at least two card units and no
      #   heading outside them, the label heads a section ({#section?}) and every destination in it is
      #   marked; such a label sits in a header, never in a card: beside card units, its wrapper holds nothing
      #   but the label (an ad box holding a slot is no header). A section is never a page region
      #   ({PAGE_REGIONS}).
      #
      # Marking is per card: a URL is sponsored only when every anchor to it sits in a marked card,
      # so a promo slot never hides the editorial card linking the same story.
      class SponsoredCards
        # Elements that hold a page, never a section: a section label stops below them.
        PAGE_REGIONS = Set[:html, :body, :main].freeze
        # Text that holds a word.
        WORD = /[[:alnum:]]/

        LinkedLabel = Data.define(:range, :headings)
        ##
        # A label inside an anchor, climbing to its card unit: the anchor range and heading count of the
        # largest one-card unit around it so far. It starts empty and takes the anchor's frame first.
        class LinkedLabel
          # A unit not yet measured.
          OPEN = new(range: (0...0), headings: 0)
        end

        # A +:paid_label+ outside every anchor, climbing to the section it may head: the label node and the
        # anchor count before and after it.
        SectionLabel = Data.define(:label, :before, :after)

        private_constant :LinkedLabel, :SectionLabel

        # @param document [SST::Document, nil]
        # @param link_resolver [Scoring::LinkResolver, nil]
        def initialize(document, link_resolver)
          @claims = AnchorClaims.new(link_resolver)
          @linked = Set.new
          @ancestors, @labelled, @links = Array.new(3) { [] }
          @headings = 0
          # Linked labels still climbing at the root bind there.
          walk(document.root)&.each { bind_link(_1) if _1.is_a?(LinkedLabel) } if document
          @keys = @claims.sponsored_keys
          freeze
        end

        # @param key [Array] article identity
        # @return [Boolean]
        def include?(key) = @keys.include?(key)

        private

        # Returns the labels still climbing out of +node+ (nil when none). +@labelled+ holds one flag per
        # open card, innermost last; +@links+ the anchor index of each open anchor.
        def walk(node)
          start = @claims.size
          headings = @headings
          card = LinkDestination::Sponsorship::CARD_NAMES.include?(node.name)
          @labelled << false if card
          pending = mark(node, start, descend(node))
          pending = append(pending, [LinkedLabel::OPEN]) if node.link? && @linked.delete?(start)
          bound = bind(start) if card && @labelled.pop
          pending && settle(node, start, @headings - headings, pending, bound:)
        end

        def descend(node)
          link = node.link?
          record(node) if link
          @headings += 1 if node.heading?
          @ancestors << node
          pending = nil
          node.children.each { pending = append(pending, walk(_1)) }
          @ancestors.pop
          @links.pop if link
          pending
        end

        def record(anchor) = @links << @claims.record(anchor, in_heading: @ancestors.any?(&:heading?))

        def mark(node, start, pending)
          marker = LinkDestination::Sponsorship.marker(node, @ancestors)
          return pending unless marker
          return pending.tap { @claims.claim(start...@claims.size) } if marker == :container && @claims.size > start
          return pending.tap { @linked << @links.last } unless @links.empty?

          @labelled[-1] = true unless @labelled.empty?
          return pending unless marker == :paid_label

          append(pending, [SectionLabel.new(label: node, before: start, after: @claims.size)])
        end

        def append(pending, labels) = pending && labels ? pending.concat(labels) : pending || labels

        # Moves each climbing label to +node+'s frame; returns the labels that climb on. A section label
        # stops at a card or page region: {#section?} would reject anything above, so it saves the survey.
        def settle(node, start, headings, pending, bound:)
          range = start...@claims.size
          boundary = LinkDestination::Sponsorship::CARD_NAMES.include?(node.name) || PAGE_REGIONS.include?(node.name)
          climbing = pending.filter_map do |label|
            case label
            in LinkedLabel then climb(label, range, headings)
            in SectionLabel then head(label, node, range, boundary:, bound:)
            end
          end
          climbing unless climbing.empty?
        end

        # Grows a linked label's unit while it stays one card; binds it at the first crowded frame.
        def climb(label, range, headings)
          crowded = Html::CardWalk.crowded?(heading_count: headings, distinct_main_hrefs: @claims.keys_in(range).size)
          crowded ? bind_link(label) : label.with(range:, headings:)
        end

        # Claims the unit (one destination at most) when it holds a heading; returns nil.
        def bind_link(label)
          @claims.claim(label.range) if label.headings == 1
          nil
        end

        # A section label stops at a bound card, at an anchor before it, and at a card or page region holding
        # no destination after it. At its first frame holding one it marks that card or section, then stops.
        def head(label, node, range, boundary:, bound:)
          return if bound || range.begin < label.before
          return (label unless boundary) unless range.end > label.after

          units = CardUnits.new(node, skip: label.label, claims: @claims)
          @claims.claim(range) if units.card? || section?(node, label.label, units)
          nil
        end

        # Whether +label+ heads +node+ as a section: no page region, at least two card units and no heading
        # outside them, and the label in a header (holding only the label when card units sit beside it).
        def section?(node, label, units)
          return false if node.find { PAGE_REGIONS.include?(_1.name) }

          units.cards >= 2 && units.stray.zero? && (units.peers.zero? || alone?(node, label))
        end

        # Whether the child of +node+ around +label+ holds nothing but the label.
        def alone?(node, label)
          wrapper = node.children.find { SST::Index.descendant_or_self?(label, _1) }
          until wrapper.equal?(label)
            return false unless wrapper.children.one? && !wrapper.own_text.match?(WORD)

            wrapper = wrapper.children.first
          end
          true
        end

        def bind(start)
          range = start...@claims.size
          key = @claims.dominant_key(range)
          @claims.claim(range, [key]) if key
        end
      end
      private_constant :SponsoredCards
    end
  end
end
