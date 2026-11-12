# frozen_string_literal: true

module Html2rss
  module SST
    ##
    # Visible-text extraction for SST nodes (port of Navigator::TextExtractor).
    #
    # Block children separate by a newline (or the given separator); other neighbours by one space,
    # except where an inline element embedded in direct text touches it with no whitespace between them
    # in the source: +Straßenbah<span>n</span> für+ stays one word. Two adjacent elements, and an element
    # opening or closing its parent's text (+<span>Live</span>Headline+), always separate, since sites
    # lay out such spans as blocks with CSS.
    module Text
      # One piece of a node's text: direct text or one child's text, whether it is a block, and whether it
      # glues to the piece before it (no whitespace between them in the source).
      Fragment = Data.define(:text, :block, :glue)
      private_constant :Fragment

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

        # Ordered fragments: lead text, then each shown child followed by the text after it.
        def fragments(node, separator, excluded)
          raws = [node.lead_text, *node.tails]
          pieces = [direct_fragment(raws.first, false)]
          node.children.each_with_index do |child, index|
            next pieces << direct_fragment(raws[index + 1], false) unless shown?(child, excluded)

            pieces.push(*shown_fragments(child, raws, index, separator, excluded))
          end
          pieces
        end

        # A shown child and the direct text after it. Only a child embedded in direct text (text on both
        # sides) glues to it, where they meet with no whitespace between them: a leading or trailing span
        # beside text (+<span>Live</span>Headline+) is a styled label more often than part of a word.
        def shown_fragments(child, raws, index, separator, excluded)
          before = raws[index].to_s
          after = raws[index + 1].to_s
          embedded = !before.empty? && !after.empty?
          [child_fragment(child, separator, excluded, embedded && before.match?(/\S\z/) && opens_word?(child)),
           direct_fragment(after, embedded && closes_word?(child) && after.match?(/\A\S/))]
        end

        # Whether the raw text of +node+ starts with a non-space, descending into its first child while it
        # has no lead text.
        def opens_word?(node)
          first = node.children.first
          node.lead_text.empty? && first ? opens_word?(first) : node.lead_text.match?(/\A\S/)
        end

        # Whether the raw text of +node+ ends with a non-space, descending into its last child while no
        # text follows it.
        def closes_word?(node)
          raw = node.tails.last || node.own_text
          last = node.children.last
          raw.empty? && last ? closes_word?(last) : raw.match?(/\S\z/)
        end

        def join_fragments(pieces, separator)
          last_block = nil
          parts = pieces.each_with_object([]) do |piece, out|
            next if piece.text.empty?

            out << gap(separator, piece, last_block) unless last_block.nil?
            out << piece.text
            last_block = piece.block
          end
          parts.join unless parts.empty?
        end

        def gap(separator, piece, last_block)
          return (separator == ' ' ? "\n" : separator) if piece.block || last_block

          piece.glue ? '' : ' '
        end

        def shown?(child, excluded) = !excluded&.[](child) && visible_child?(child)

        def squish(text) = text.to_s.gsub(/\s+/, ' ').strip

        def direct_fragment(raw, glue) = Fragment.new(squish(raw), false, glue)

        def child_fragment(child, separator, excluded, glue)
          Fragment.new(child_text(child, separator, excluded), Tags::BLOCK_NAMES.include?(child.name), glue)
        end

        # A leaf's text is read directly (no fragments to join), the hot path of every text read.
        def child_text(child, separator, excluded)
          text = if child.children.empty?
                   squish(child.own_text)
                 else
                   extract(child, separator:, exclude: excluded&.keys).to_s
                 end
          child.name == :li && !text.empty? ? "- #{text}" : text
        end

        def visible_child?(node)
          !Tags::INVISIBLE_NAMES.include?(node.name) &&
            !(node.name == :a && node.attrs.href&.start_with?('#'))
        end
      end
    end
  end
end
