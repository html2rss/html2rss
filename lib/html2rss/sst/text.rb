# frozen_string_literal: true

module Html2rss
  module SST
    ##
    # Visible-text extraction for SST nodes (port of Html::Navigator::TextExtractor).
    module Text
      module_function

      ##
      # @param node [Node]
      # @param separator [String]
      # @param exclude [Array<Node>, nil]
      # @return [String, nil]
      def extract(node, separator: ' ', exclude: nil)
        raise ArgumentError, 'node is required' unless node

        excluded = exclude ? Set.new(exclude) : nil
        parts = collect_parts(node, separator, excluded)
        return if parts.empty?

        parts.join.squeeze(' ').strip
      end

      def collect_parts(node, separator, excluded)
        last_block = false
        node.children.each_with_object([]) do |child, parts|
          next if excluded&.include?(child)
          next unless visible_child?(child)

          text, block = child_text_and_block(child, separator, excluded)
          next if text.empty?

          append_separator!(parts, separator, block, last_block)
          parts << text
          last_block = block
        end
      end
      module_function :collect_parts
      private_class_method :collect_parts

      def child_text_and_block(child, separator, excluded)
        text = if child.children.empty?
                 child.own_text.gsub(/\s+/, ' ').strip
               else
                 extract(child, separator:, exclude: excluded&.to_a).to_s.strip
               end
        text = "- #{text}" if child.name == :li && !text.empty?
        [text, Tags::BLOCK_NAMES.include?(child.name)]
      end
      module_function :child_text_and_block
      private_class_method :child_text_and_block

      def append_separator!(parts, separator, is_block, last_was_block)
        return if parts.empty?

        parts << if is_block || last_was_block
                   (separator == ' ' ? "\n" : separator)
                 else
                   ' '
                 end
      end
      module_function :append_separator!
      private_class_method :append_separator!

      def visible_child?(node)
        !Tags::INVISIBLE_NAMES.include?(node.name) &&
          !(node.name == :a && node.attrs.href&.start_with?('#'))
      end
      module_function :visible_child?
      private_class_method :visible_child?
    end
  end
end
