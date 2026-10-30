# frozen_string_literal: true

module Html2rss
  module SST
    ##
    # Visible-text extraction for SST nodes (port of Navigator::TextExtractor).
    module Text
      class << self
        ##
        # @param node [Node]
        # @param separator [String]
        # @param exclude [Array<Node>, nil]
        # @return [String, nil]
        def extract(node, separator: ' ', exclude: nil)
          raise ArgumentError, 'node is required' unless node

          excluded = exclude&.each_with_object({}.compare_by_identity) { |n, h| h[n] = true }
          parts = collect_parts(node, separator, excluded)
          own = node.own_text.gsub(/\s+/, ' ').strip
          parts.unshift(own) unless own.empty?
          return if parts.empty?

          parts.join
        end

        private

        def collect_parts(node, separator, excluded)
          last_block = false
          node.children.each_with_object([]) do |child, parts|
            next if excluded&.[](child)
            next unless visible_child?(child)

            text, block = child_text_and_block(child, separator, excluded)
            next if text.empty?

            append_separator!(parts, separator, block, last_block)
            parts << text
            last_block = block
          end
        end

        def child_text_and_block(child, separator, excluded)
          text = if child.children.empty?
                   child.own_text.gsub(/\s+/, ' ').strip
                 else
                   extract(child, separator:, exclude: excluded&.keys).to_s.strip
                 end
          text = "- #{text}" if child.name == :li && !text.empty?
          [text, Tags::BLOCK_NAMES.include?(child.name)]
        end

        def append_separator!(parts, separator, is_block, last_was_block)
          return if parts.empty?

          parts << if is_block || last_was_block
                     (separator == ' ' ? "\n" : separator)
                   else
                     ' '
                   end
        end

        def visible_child?(node)
          !Tags::INVISIBLE_NAMES.include?(node.name) &&
            !(node.name == :a && node.attrs.href&.start_with?('#'))
        end
      end
    end
  end
end
