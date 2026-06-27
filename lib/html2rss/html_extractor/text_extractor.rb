# frozen_string_literal: true

module Html2rss
  class HtmlExtractor
    ##
    # TextExtractor extracts visible text from DOM elements, preserving lists
    # and block spacing while sanitizing white spaces.
    class TextExtractor
      # HTML block elements that trigger line breaks or special formatting.
      BLOCK_TAGS = %w[p div li ul ol h1 h2 h3 h4 h5 h6 tr br].to_set.freeze
      # Tags ignored when extracting visible text content.
      INVISIBLE_CONTENT_TAGS = %w[svg script noscript style template].to_set.freeze

      class << self
        ##
        # @param tag [Nokogiri::XML::Node] the node from which to extract visible text
        # @param separator [String] separator used to join text fragments (default is a space)
        # @param exclude_nodes [Array<Nokogiri::XML::Node>, nil] nodes to exclude from extraction
        # @return [String, nil] the concatenated visible text, or nil if none is found
        def call(tag, separator: ' ', exclude_nodes: nil)
          return tag.text.gsub(/\s+/, ' ').strip if tag.respond_to?(:text?) && tag.text?

          parts = iterate_children(tag, separator, exclude_nodes)
          parts.join.squeeze(' ').gsub(/[ \t\r]*(\n|<br>)[ \t\r]*/, '\1').strip unless parts.empty?
        end

        private

        def iterate_children(tag, separator, exclude_nodes)
          last = false
          tag.children.each_with_object([]) do |c, p|
            next if exclude_nodes&.include?(c) || !visible_child?(c)

            text, block = process_child_node(c, separator, exclude_nodes)
            next if text.empty?

            append_separator!(p, separator, block, last)
            (p << text) && (last = block)
          end
        end

        def process_child_node(child, separator, exclude_nodes)
          child_text = get_child_text(child, separator, exclude_nodes)
          return ['', false] if child_text.empty?

          child_text = "- #{child_text}" if child.name == 'li'
          [child_text, BLOCK_TAGS.include?(child.name)]
        end

        def get_child_text(child, separator, exclude_nodes)
          if child.children.empty?
            child.text.to_s.gsub(/\s+/, ' ').strip
          else
            call(child, separator:, exclude_nodes:).to_s.strip
          end
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
          !INVISIBLE_CONTENT_TAGS.include?(node.name) &&
            !(node.name == 'a' && node['href']&.start_with?('#'))
        end
      end
    end
  end
end
