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

      # SST reads of the rule.
      module SstNodes
        def self.marked(root)
          root.find_all { |node| node.attrs.raw.key?(KICKER_ATTRIBUTE) || node.attrs.class_names.any?(KICKER_CLASS) }
        end

        def self.elements(node) = node.descendants
        def self.text(node, exclude = []) = node.visible_text(exclude: (exclude unless exclude.empty?))
        def self.time?(node) = node.name == :time

        def self.inside?(node, ancestor)
          return true if node.equal?(ancestor)

          index = SST::Index.for_node(node)
          index ? index.descendant_of?(node, ancestor) : !ancestor.find { _1.equal?(node) }.nil?
        end
      end

      # Nokogiri reads of the rule.
      module DomNodes
        def self.marked(root)
          root.xpath('descendant-or-self::*[@class or @data-tb-kicker]')
              .select { |node| node.key?(KICKER_ATTRIBUTE) || node['class'].match?(KICKER_CLASS) }
        end

        def self.elements(node) = node.css('*')
        def self.text(node, exclude = nil) = Navigator.extract_visible_text(node, exclude_nodes: exclude)
        def self.time?(node) = node.name == 'time'
        def self.inside?(node, ancestor) = node == ancestor || Navigator.descendant_of?(node, ancestor)
      end
      private_constant :WORD, :SstNodes, :DomNodes

      ##
      # @param root [Nokogiri::XML::Node, SST::Node] card root
      # @param source [Nokogiri::XML::Node, SST::Node, nil] headline source: the heading, else the anchor
      def initialize(root, source)
        @root = root
        @source = source
        @nodes = root.instance_of?(SST::Node) ? SstNodes : DomNodes
      end

      ##
      # @return [Nokogiri::XML::Node, SST::Node, nil] the kicker element (memoized, also when nil)
      def kicker
        return @kicker if defined?(@kicker)

        candidates = @nodes.marked(@root).select { kicker_text?(_1) && beside_headline?(_1) }
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
        @nodes.elements(node).each do |element|
          next unless noise_element?(element)
          break unless opening?(node, dropped, element)

          dropped << element
        end
        @nodes.text(node, dropped)
      end

      private

      def noise_element?(node) = @nodes.time?(node) || Article::Title.headline_noise_piece?(@nodes.text(node))

      # Whether +element+ opens the text of +node+ left after +dropped+.
      def opening?(node, dropped, element) = @nodes.text(node, dropped).to_s.start_with?(@nodes.text(element).to_s)

      def kicker_text?(node) = !noise_element?(node) && text_without_noise(node).to_s.match?(WORD)

      def text_without_noise(node) = @nodes.text(node, kicker_noise(node))

      # Kicker pieces that are noise on their own: +time+ elements and {Article::Title.noise_piece?}.
      def kicker_noise(node)
        @nodes.elements(node).select { @nodes.time?(_1) || Article::Title.noise_piece?(@nodes.text(_1)) }
      end

      def beside_headline?(node)
        return true unless @source
        return false if @nodes.inside?(@source, node)

        !@nodes.inside?(node, @source) || @nodes.text(@source, [node]).to_s.match?(WORD)
      end

      # Whether +node+ holds no word outside its noise and its nested kicker candidates.
      def parts_only?(node, candidates)
        parts = candidates.select { |other| !other.equal?(node) && @nodes.inside?(other, node) }
        return true if parts.empty?

        !@nodes.text(node, kicker_noise(node) + parts).to_s.match?(WORD)
      end
    end
  end
end
