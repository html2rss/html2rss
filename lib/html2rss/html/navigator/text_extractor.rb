# frozen_string_literal: true

module Html2rss
  module Html
    class Navigator
      ##
      # TextExtractor extracts visible text from DOM elements, preserving lists
      # and block spacing while sanitizing white spaces. Same joining rule as {SST::Text}: an inline element
      # embedded in direct text and touching it stays in its word (+Straßenbah<span>n</span> für+), while two
      # adjacent elements and an element opening or closing its parent's text always separate.
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
            return tag.text.gsub(/\s+/, ' ').strip if tag.is_a?(Nokogiri::XML::Text)

            parts = iterate_children(tag, separator, exclude_nodes)
            return if parts.empty?

            parts.join.squeeze(' ').strip
          end

          private

          # +last+ is [node, block?] of the previous piece with text.
          def iterate_children(tag, separator, exclude_nodes)
            last = nil
            tag.children.each_with_object([]) do |c, parts|
              text, block = process_child_node(c, separator, exclude_nodes) if shown?(c, exclude_nodes)
              next if text.to_s.empty?

              parts << gap(separator, block, last, c) if last
              parts << text
              last = [c, block]
            end
          end

          def shown?(child, exclude_nodes) = !exclude_nodes&.include?(child) && visible_child?(child)

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

          def gap(separator, is_block, last, child)
            return (separator == ' ' ? "\n" : separator) if is_block || last.last

            touching?(last.first, child) ? '' : ' '
          end

          # Whether direct text and an inline element meet as adjacent siblings with no whitespace between
          # them. Only an element embedded in direct text (a text sibling on both sides) touches it.
          def touching?(before, after)
            element = before.element? ? before : after
            before.next_sibling == after && embedded?(element) &&
              !before.text.match?(/\s\z/) && !after.text.match?(/\A\s/)
          end

          def embedded?(element) = element.previous_sibling&.text? && element.next_sibling&.text?

          def visible_child?(node)
            !INVISIBLE_CONTENT_TAGS.include?(node.name) &&
              !(node.name == 'a' && node['href']&.start_with?('#'))
          end
        end
      end
    end
  end
end
