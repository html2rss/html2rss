# frozen_string_literal: true

module Html2rss
  module Html
    ##
    # Backend-agnostic predicates for HTML/XML nodes returned from CSS queries.
    #
    # Nodes stay backend-native for allocation locality; this module is the
    # type-check surface that replaces +is_a?(Nokogiri::XML::Node)+ gates.
    module Node
      module_function

      ##
      # @param obj [Object]
      # @return [Boolean]
      def node?(obj)
        return true if obj.is_a?(Document)
        return true if Backend::Nokogiri.node?(obj)
        return true if Backend::Rust.node?(obj)

        Backend::Nokolexbor.node?(obj)
      rescue LoadError
        false
      end

      ##
      # @param obj [Object]
      # @return [Boolean]
      def node_set?(obj)
        return true if Backend::Nokogiri.node_set?(obj)
        return true if Backend::Rust.node_set?(obj)

        Backend::Nokolexbor.node_set?(obj)
      rescue LoadError
        false
      end

      ##
      # @param obj [Object, Document, nil]
      # @return [Object, nil] backend-native node
      def unwrap(obj)
        obj.is_a?(Document) ? obj.native : obj
      end

      ##
      # Descendant text nodes without a general XPath engine.
      #
      # Prefers a backend named helper (+descendant_texts+); falls back to
      # Nokogiri +xpath('.//text()')+ when present.
      #
      # @param node [Object]
      # @return [Array<Object>]
      def descendant_texts(node)
        return [] unless node
        return node.descendant_texts.to_a if node.respond_to?(:descendant_texts)
        return node.xpath('.//text()').to_a if node.respond_to?(:xpath)

        []
      end

      ##
      # First non-blank descendant text content.
      #
      # @param node [Object]
      # @return [String, nil]
      def first_nonblank_text(node)
        descendant_texts(node).lazy.map { |t| t.text.to_s.strip }.find { !_1.empty? }
      end

      ##
      # Visible (non script/style/noscript) descendant text length.
      #
      # @param node [Object]
      # @return [Integer]
      def visible_text_length(node)
        descendant_texts(node)
          .reject { invisible_text_ancestor?(_1) }
          .map(&:text)
          .join(' ')
          .gsub(/\s+/, ' ')
          .strip
          .length
      end

      ##
      # @param text_node [Object]
      # @return [Boolean]
      def invisible_text_ancestor?(text_node)
        curr = text_node.respond_to?(:parent) ? text_node.parent : nil
        while curr
          return true if %w[script style noscript].include?(Probe.tag(curr))

          curr = curr.respond_to?(:parent) ? curr.parent : nil
        end
        false
      end
    end
  end
end
