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
      # - A +:paid_label+ outside every anchor may also head a section ({#section?}): the nearest ancestor,
      #   up to its card, that it opens (no anchor before it) and that holds at least two card units and no
      #   heading outside them. Every destination of the section is marked. A section is never a page region
      #   ({PAGE_REGIONS}), and a card that binds its dominant destination is no section.
      #
      # Marking is per card: a URL is sponsored only when every anchor to it sits in a marked card,
      # so a promo slot never hides the editorial card linking the same story.
      class SponsoredCards
        # Elements that hold a page, never a section: a section label stops below them.
        PAGE_REGIONS = Set[:html, :body, :main].freeze

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

        # A section label stops at a bound card, at an anchor before it, at its section or at a boundary.
        def head(label, node, range, boundary:, bound:)
          return if bound || range.begin < label.before

          if range.end > label.after && section?(node, label.label)
            @claims.claim(range)
            return
          end

          label unless boundary
        end

        # Whether +node+ is a section: no page region, at least two card units and no heading outside them.
        def section?(node, label)
          return false if node.find { PAGE_REGIONS.include?(_1.name) }

          units = CardUnits.new(node, skip: label, claims: @claims)
          units.cards >= 2 && units.stray.zero?
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
