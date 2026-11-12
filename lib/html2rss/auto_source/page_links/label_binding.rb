# frozen_string_literal: true

module Html2rss
  class AutoSource
    class PageLinks
      ##
      # Whether a +:paid_label+ outside every anchor marks the frame where it binds: its first ancestor
      # holding a destination after it ({SponsoredCards}). The label marks that frame when
      #
      # - it captions no ad slot ({#ad_caption?}), and
      # - the frame is one card unit with a heading ({CardUnits#card?}), or a section: no page region, at
      #   least two card units, no heading outside them, and, when card units sit beside the label, a
      #   wrapper holding nothing but the label ({#alone?}).
      class LabelBinding
        # Elements that hold a page, never a section: a section label stops below them.
        PAGE_REGIONS = Set[:html, :body, :main].freeze
        # Text that holds a word.
        WORD = /[[:alnum:]]/
        # Box elements that can be an ad slot: layout boxes and the +ins+ element ad scripts fill.
        SLOT_NAMES = (SST::Tags::LAYOUT_NAMES | Set[:ins]).freeze
        # Media elements: a box holding one shows a picture (a sponsor logo), not an empty slot.
        MEDIA_NAMES = Set[:img, :picture, :video].freeze
        private_constant :WORD, :SLOT_NAMES, :MEDIA_NAMES

        ##
        # @param node [SST::Node] the frame where the label binds
        # @param label [SST::Node] the label element
        # @param claims [AnchorClaims] resolves the frame's destinations
        def initialize(node, label, claims)
          @node = node
          @label = label
          @claims = claims
        end

        ##
        # @return [Boolean] whether the label marks every destination of the frame
        def marks?
          return false if ad_caption?

          units = CardUnits.new(@node, skip: @label, claims: @claims)
          units.card? || section?(units)
        end

        private

        def section?(units)
          return false if @node.find { PAGE_REGIONS.include?(_1.name) }

          units.cards >= 2 && !units.stray? && (!units.peers? || alone?)
        end

        # Whether the child of the frame around the label holds nothing but the label.
        def alone?
          wrapper = @node.children.find { SST::Index.descendant_or_self?(@label, _1) }
          until wrapper.equal?(@label)
            return false unless wrapper.children.one? && !wrapper.own_text.match?(WORD)

            wrapper = wrapper.children.first
          end
          true
        end

        # Whether the label captions an ad slot: an empty box ({#slot?}) sits beside the label, or beside one
        # of its wrappers below the frame, before the first sibling holding a destination. That box is the
        # space an ad fills at load, so the cards after it are editorial.
        def ad_caption?
          index = SST::Index.for_node(@label)
          child = @label
          until child.equal?(@node)
            parent = index.parent_of(child)
            return true if slot_beside?(parent)

            child = parent
          end
          false
        end

        # The label and its wrappers below the frame hold no destination and no slot, so the run of
        # children before the first one holding a destination is the label's neighbourhood at that level.
        def slot_beside?(parent) = parent.children.take_while { !_1.find(&:link?) }.any? { slot?(_1) }

        # An empty box: a layout or +ins+ element holding no words, no link and no media.
        def slot?(node)
          SLOT_NAMES.include?(node.name) && !node.find { _1.link? || MEDIA_NAMES.include?(_1.name) } &&
            !node.visible_text.to_s.match?(WORD)
        end
      end
      private_constant :LabelBinding
    end
  end
end
