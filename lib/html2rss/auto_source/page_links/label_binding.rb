# frozen_string_literal: true

module Html2rss
  class AutoSource
    class PageLinks
      ##
      # Whether a +:paid_label+ outside every anchor marks the frame where it binds: its first ancestor
      # holding a destination after it ({SponsoredCards}). The label marks that frame when it is
      #
      # - the label of one card: the frame is one card unit with a heading ({CardUnits#card?}) and the label
      #   sits in it alone ({#alone?}), not in a box beside the card that holds more (an ad slot); or
      # - the header of a section ({#header?}): the frame is no page region and holds no heading outside its
      #   card units.
      #
      # A label in plain text before cards (an ad caption over an empty or stripped slot) heads nothing.
      class LabelBinding
        # Elements that hold a page, never a section: a section label stops below them.
        PAGE_REGIONS = Set[:html, :body, :main].freeze
        # Class-token words (split on +-+/+_+) of a header box.
        HEADER_WORDS = Set['header', 'head', 'heading'].freeze
        # Text that holds a word.
        WORD = /[[:alnum:]]/
        private_constant :HEADER_WORDS, :WORD

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
          units = CardUnits.new(@node, skip: @label, claims: @claims)
          (units.card? && alone?) || section?(units)
        end

        private

        def section?(units)
          return false if @node.find { PAGE_REGIONS.include?(_1.name) }

          !units.stray? && header?
        end

        # Whether the label heads the frame: it sits in the frame's first child holding words, and it or a
        # wrapper of it there is a heading, a +header+ element or a header box ({HEADER_WORDS}).
        def header?
          first = @node.children.find { _1.visible_text.to_s.match?(WORD) }
          path.last.equal?(first) && path.any? { _1.heading? || _1.name == :header || header_box?(_1) }
        end

        def header_box?(node)
          node.attrs.class_names.any? { |token| token.downcase.split(/[-_]+/).any? { HEADER_WORDS.include?(_1) } }
        end

        # Whether the frame's child around the label holds nothing but the label.
        def alone?
          path.drop(1).all? { _1.children.one? && !_1.own_text.match?(WORD) }
        end

        # The label and its wrappers up to the frame's child holding it, innermost first.
        def path
          @path ||= begin
            index = SST::Index.for_node(@label)
            nodes = [@label]
            nodes << index.parent_of(nodes.last) until index.parent_of(nodes.last).equal?(@node)
            nodes
          end
        end
      end
      private_constant :LabelBinding
    end
  end
end
