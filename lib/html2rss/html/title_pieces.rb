# frozen_string_literal: true

module Html2rss
  module Html
    ##
    # Picks the kicker and the headline text of one teaser card: the one rule shared by
    # {ArticleExtractor} (Nokogiri) and {SstArticleExtractor} (SST), so both give one title for the same
    # markup. The noise vocabulary and composition stay on {Article::Title}; rules: CONTEXT.md § Article title.
    #
    # The kicker is the outermost kicker-marked element beside the headline that carries kicker text and
    # holds no word besides its noise and kicker-marked parts (+kicker__topic+ and +kicker__sub+ join).
    # Headline text leaves out a nested kicker and the noise elements before its first word.
    class TitlePieces
      # Class-token marks of kicker / eyebrow text.
      KICKER_CLASS = /kicker|eyebrow|pre-title|pretitle|overline/i
      # Attribute marking kicker text.
      KICKER_ATTRIBUTE = 'data-tb-kicker'
      # Text that holds a word.
      WORD = /[[:alnum:]]/

      # +time+ element names of both node kinds.
      TIME_NAMES = Set['time', :time].freeze
      private_constant :WORD, :TIME_NAMES

      ##
      # @param root [Nokogiri::XML::Node, SST::Node] card root
      # @param source [Nokogiri::XML::Node, SST::Node, nil] headline source: the heading, else the anchor
      def initialize(root, source)
        @root = root
        @source = source
        @sst = root.instance_of?(SST::Node)
      end

      ##
      # @return [Nokogiri::XML::Node, SST::Node, nil] the kicker element (memoized, also when nil)
      def kicker
        return @kicker if defined?(@kicker)

        candidates = marked.select { kicker_text?(_1) && beside_headline?(_1) }
        @kicker = candidates.find { |node| parts_only?(node, candidates) }
      end

      ##
      # @return [String, nil] kicker text without its noise pieces ({Article::Title.noise_piece?})
      def kicker_text = kicker && text_without_noise(kicker)

      ##
      # @param node [Nokogiri::XML::Node, SST::Node, nil] heading, its title child, or the anchor
      # @return [String, nil] its text without a nested kicker and the noise elements opening it
      def headline_text(node)
        return unless node

        dropped = [kicker].compact
        elements(node).each do |element|
          next unless noise_element?(element)
          break unless opening?(node, dropped, element)

          dropped << element
        end
        text(node, dropped)
      end

      private

      # Node reads: SST nodes or Nokogiri nodes.
      def marked
        return @root.find_all { _1.attrs.raw.key?(KICKER_ATTRIBUTE) || _1.attrs.class_names.any?(KICKER_CLASS) } if @sst

        @root.xpath('descendant-or-self::*[@class or @data-tb-kicker]')
             .select { _1.key?(KICKER_ATTRIBUTE) || _1['class'].match?(KICKER_CLASS) }
      end

      def elements(node) = @sst ? node.descendants : node.css('*')
      def time?(node) = TIME_NAMES.include?(node.name)

      # SST memoizes text read without exclusions.
      def text(node, exclude = nil)
        return Navigator.extract_visible_text(node, exclude_nodes: exclude) unless @sst

        exclude&.any? ? node.visible_text(exclude:) : node.visible_text
      end

      # Whether +node+ is +ancestor+ or inside it.
      def inside?(node, ancestor)
        return SST::Index.descendant_or_self?(node, ancestor) if @sst

        node == ancestor || Navigator.descendant_of?(node, ancestor)
      end

      def noise_element?(node) = time?(node) || Article::Title.headline_noise_piece?(text(node))

      # Whether +element+ opens the text of +node+ left after +dropped+.
      def opening?(node, dropped, element) = text(node, dropped).to_s.start_with?(text(element).to_s)

      def kicker_text?(node) = !noise_element?(node) && text_without_noise(node).to_s.match?(WORD)

      def text_without_noise(node) = text(node, kicker_noise(node))

      # Kicker pieces that are noise on their own: +time+ elements and {Article::Title.noise_piece?}.
      def kicker_noise(node)
        elements(node).select { time?(_1) || Article::Title.noise_piece?(text(_1)) }
      end

      def beside_headline?(node)
        return true unless @source
        return false if inside?(@source, node)

        !inside?(node, @source) || text(@source, [node]).to_s.match?(WORD)
      end

      # Whether +node+ holds no word outside its noise and its nested kicker candidates.
      def parts_only?(node, candidates)
        parts = candidates.select { |other| !other.equal?(node) && inside?(other, node) }
        return true if parts.empty?

        !text(node, kicker_noise(node) + parts).to_s.match?(WORD)
      end
    end
  end
end
