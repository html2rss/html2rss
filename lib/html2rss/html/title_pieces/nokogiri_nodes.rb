# frozen_string_literal: true

module Html2rss
  module Html
    class TitlePieces
      ##
      # {Nodes} reads of Nokogiri nodes: direct text is the text node siblings of an element.
      class NokogiriNodes < Nodes
        ##
        # @param root [Nokogiri::XML::Node]
        # @param attribute [String]
        # @return [Array<Nokogiri::XML::Element>] +root+ and its descendants carrying a class or +attribute+
        def carrying(root, attribute) = root.xpath("descendant-or-self::*[@class or @#{attribute}]")

        ##
        # @param node [Nokogiri::XML::Node]
        # @return [Array<String>] class tokens
        def class_names(node) = node['class'].to_s.split

        ##
        # @param node [Nokogiri::XML::Node]
        # @param name [String]
        # @return [String, nil] the attribute value
        def attribute(node, name) = node[name]

        ##
        # @param node [Nokogiri::XML::Node]
        # @return [Nokogiri::XML::Node, nil]
        def parent(node) = node.parent

        ##
        # @param node [Nokogiri::XML::Node]
        # @param ancestor [Nokogiri::XML::Node]
        # @return [Boolean] whether +node+ is +ancestor+ or inside it
        def inside?(node, ancestor) = node == ancestor || Navigator.descendant_of?(node, ancestor)

        ##
        # @param node [Nokogiri::XML::Node]
        # @return [Boolean] whether +node+'s direct text (outside its child elements) holds a word
        def own_words?(node) = node.children.any? { _1.text? && _1.text.match?(WORD) }

        ##
        # @param node [Nokogiri::XML::Node]
        # @return [Array<Nokogiri::XML::Node>, nil] siblings before +node+, or nil when direct text holding a
        #   word sits between them and +node+
        def siblings_before(node)
          before = []
          sibling = node.previous_sibling
          while sibling
            return if sibling.text? && sibling.text.match?(WORD)

            before.unshift(sibling)
            sibling = sibling.previous_sibling
          end
          before
        end

        private

        def descendants(node) = node.css('*')
        def style(node) = node['style']
        def visible_text(node, exclude) = Navigator.extract_visible_text(node, exclude_nodes: exclude)

        # The direct text right before and right after +node+.
        def texts_beside(node) = [node.previous_sibling, node.next_sibling].map { _1.text if _1&.text? }
      end
      private_constant :NokogiriNodes
    end
  end
end
