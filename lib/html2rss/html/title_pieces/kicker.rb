# frozen_string_literal: true

module Html2rss
  module Html
    class TitlePieces
      ##
      # The kicker of one card, first match: the outermost kicker-marked element beside the headline
      # ({KICKER_WORDS}, {KICKER_ATTRIBUTE}) holding no word besides its noise and kicker-marked parts; else
      # a label leaf ({LABEL_WORDS}) opening the heading or anchor text; else the piece right before the
      # headline piece. A paid-content label is never a kicker.
      class Kicker
        # Media element names of both node kinds: a piece holding one is a picture, not a kicker.
        MEDIA_NAMES = Set['img', 'picture', 'figure', 'video', 'svg', :img, :picture, :figure, :video, :svg].freeze
        # Paragraphs of both node kinds: running prose, never a kicker.
        PARAGRAPH_NAMES = Set['p', :p].freeze
        private_constant :MEDIA_NAMES, :PARAGRAPH_NAMES

        ##
        # @param nodes [Nodes] reader of the card's nodes
        # @param root [Nokogiri::XML::Node, SST::Node] card root
        # @param source [Nokogiri::XML::Node, SST::Node, nil] headline source: the heading, else the anchor
        # @yieldreturn [Nokogiri::XML::Node, SST::Node, nil] the source's headline piece, read only when
        #   no marked or label kicker is found
        def initialize(nodes, root, source, &)
          @nodes = nodes
          @root = root
          @source = source
          @element = marked || (label || preceding(yield) if source)
        end

        ##
        # @return [Nokogiri::XML::Node, SST::Node, nil] the kicker element
        attr_reader :element

        ##
        # @return [String, nil] kicker text without its noise pieces ({Article::Title.noise_piece?})
        def text = element && text_without_noise(element)

        private

        # A kicker inside the heading or anchor wins over one beside it (a topline in the heading over a
        # type badge above it).
        def marked
          candidates = @nodes.carrying(@root, KICKER_ATTRIBUTE).select { marked?(_1) && worded?(_1) && beside?(_1) }
          kickers = candidates.select { |node| parts_only?(node, candidates) }
          kickers.find { @nodes.inside?(_1, @source) } || kickers.first
        end

        def marked?(node)
          @nodes.attribute(node, KICKER_ATTRIBUTE) || @nodes.class_words(node).intersect?(KICKER_WORDS)
        end

        # A label leaf opening the source text, with headline text after it.
        def label
          unseen = @nodes.unseen(@source)
          rest = @nodes.text(@source, unseen).to_s
          @nodes.elements(@source).find do |element|
            label_leaf?(element) && rest.start_with?(@nodes.text(element).to_s) &&
              @nodes.text(@source, unseen + [element]).to_s.match?(WORD)
          end
        end

        def label_leaf?(element) = @nodes.class_words(element).intersect?(LABEL_WORDS) && !@nodes.paid_label?(element)

        # The nearest worded piece before the headline piece, when it is a kicker-shaped leaf.
        def preceding(headline_piece)
          candidate = piece_before(headline_piece)
          return unless candidate && shaped?(candidate)

          leaf = nearest_leaf(candidate)
          leaf if shaped?(leaf)
        end

        # Walks from +piece+ up to the source, looking back over element siblings; direct text stops it.
        def piece_before(piece)
          current = piece
          until current.nil? || current.equal?(@source)
            before = @nodes.siblings_before(current)
            return if before.nil?

            worded = before.reverse.find { !skipped?(_1) }
            return worded if worded

            current = @nodes.parent(current)
          end
        end

        # Descends into the last worded child of a piece made only of elements: the leaf next to the
        # headline (a topic span after a badge in one box).
        def nearest_leaf(node)
          while !@nodes.own_words?(node) && (child = node.children.reverse.find { !skipped?(_1) })
            node = child
          end
          node
        end

        def skipped?(node)
          @nodes.concealed?(node) || @nodes.date_element?(node) || !text_without_noise(node).to_s.match?(WORD)
        end

        def shaped?(node)
          !PARAGRAPH_NAMES.include?(node.name) && !@nodes.class_words(node).intersect?(LEAD_WORDS) &&
            @nodes.elements(node).none? { MEDIA_NAMES.include?(_1.name) }
        end

        def worded?(node)
          !@nodes.date_element?(node) && !@nodes.noise?(node) && !@nodes.concealed?(node) &&
            text_without_noise(node).to_s.match?(WORD)
        end

        def text_without_noise(node) = @nodes.text(node, noise(node))

        # Kicker pieces that are noise on their own: date, time and concealed elements, paid-content labels
        # and {Article::Title.noise_piece?}.
        def noise(node)
          @nodes.elements(node).select do |piece|
            @nodes.date_element?(piece) || @nodes.concealed?(piece) || @nodes.paid_label?(piece) ||
              Article::Title.noise_piece?(@nodes.text(piece))
          end
        end

        def beside?(node)
          return true unless @source
          return false if @nodes.inside?(@source, node)

          !@nodes.inside?(node, @source) || @nodes.text(@source, [node]).to_s.match?(WORD)
        end

        # Whether +node+ holds no word outside its noise and its nested kicker candidates.
        def parts_only?(node, candidates)
          parts = candidates.select { |other| !other.equal?(node) && @nodes.inside?(other, node) }
          return true if parts.empty?

          !@nodes.text(node, noise(node) + parts).to_s.match?(WORD)
        end
      end
      private_constant :Kicker
    end
  end
end
