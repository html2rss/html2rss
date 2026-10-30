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
          join_fragments(fragments(node, separator, excluded), separator)
        end

        private

        # Ordered [text, block?] pairs: lead text, then each child followed by the text after it.
        def fragments(node, separator, excluded)
          pairs = [[squish(node.lead_text), false]]
          node.children.zip(node.tails).each do |child, tail|
            pairs << child_text_and_block(child, separator, excluded) if shown?(child, excluded)
            pairs << [squish(tail), false]
          end
          pairs
        end

        def join_fragments(pairs, separator)
          parts = []
          last_block = false
          pairs.each do |text, block|
            next if text.empty?

            append_separator!(parts, separator, block, last_block)
            parts << text
            last_block = block
          end
          parts.join unless parts.empty?
        end

        def shown?(child, excluded) = !excluded&.[](child) && visible_child?(child)

        def squish(text) = text.to_s.gsub(/\s+/, ' ').strip

        def child_text_and_block(child, separator, excluded)
          text = if child.children.empty?
                   squish(child.own_text)
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
