# frozen_string_literal: true

module Html2rss
  module Html
    class TitlePieces
      ##
      # {Nodes} reads of SST nodes: direct text is the node's lead text and the tail after each child.
      class SstNodes < Nodes
        ##
        # @param root [SST::Node]
        # @param attribute [String]
        # @return [Array<SST::Node>] +root+ and its descendants carrying a class or +attribute+
        def carrying(root, attribute) = root.find_all { _1.attrs.class_names.any? || _1.attrs.raw.key?(attribute) }

        ##
        # @param node [SST::Node]
        # @return [Array<String>] class tokens
        def class_names(node) = node.attrs.class_names

        ##
        # @param node [SST::Node]
        # @param name [String]
        # @return [String, nil] the attribute value
        def attribute(node, name) = node.attrs.raw[name]

        ##
        # @param node [SST::Node]
        # @return [SST::Node, nil] the parent of an indexed node
        def parent(node) = SST::Index.for_node(node)&.parent_of(node)

        ##
        # @param node [SST::Node]
        # @param ancestor [SST::Node]
        # @return [Boolean] whether +node+ is +ancestor+ or inside it
        def inside?(node, ancestor) = SST::Index.descendant_or_self?(node, ancestor)

        ##
        # @param node [SST::Node]
        # @return [Boolean] whether +node+'s direct text (outside its child elements) holds a word
        def own_words?(node) = node.own_text.match?(WORD)

        ##
        # @param node [SST::Node]
        # @return [Array<SST::Node>, nil] siblings before +node+, or nil when direct text holding a word
        #   sits between them and +node+
        def siblings_before(node)
          up = parent(node)
          return unless up

          index = up.children.index { _1.equal?(node) }
          up.children.take(index) unless [up.lead_text, *up.tails][..index].any? { _1.match?(WORD) }
        end

        private

        def descendants(node) = node.descendants
        def style(node) = node.attrs.style
        def visible_text(node, exclude) = node.visible_text(exclude:)

        # The direct text right before and right after +node+.
        def texts_beside(node)
          up = parent(node)
          return [] unless up

          [up.lead_text, *up.tails][up.children.index { _1.equal?(node) }, 2]
        end
      end
      private_constant :SstNodes
    end
  end
end
