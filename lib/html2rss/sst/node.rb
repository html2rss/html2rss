# frozen_string_literal: true

module Html2rss
  module SST
    ##
    # Immutable simplified semantic tree node. Predicates and traversal live on
    # the type so Scoring/Segmenter never touch Nokogiri.
    Node = Data.define(:name, :attrs, :own_text, :children, :tag_path) do
      ##
      # @param name [Symbol, String]
      # @param attrs [Attrs, nil]
      # @param own_text [String, nil]
      # @param children [Array<Node>, nil]
      # @param tag_path [String, nil] index-free ancestry path for list clustering
      # @return [Node]
      # @raise [ArgumentError] on invalid name/attrs/children
      def self.build(name:, attrs: nil, own_text: nil, children: nil, tag_path: nil)
        attrs_value = coerce_attrs(attrs)
        kids = coerce_children(children)

        new(
          name: coerce_name(name),
          attrs: attrs_value,
          own_text: own_text.to_s.freeze,
          children: kids,
          tag_path: tag_path.to_s.freeze
        )
      end

      def self.coerce_name(name)
        raise ArgumentError, 'name is required' if name.nil? || name.to_s.strip.empty?

        name.to_sym
      end
      private_class_method :coerce_name

      def self.coerce_attrs(attrs)
        attrs_value = attrs.nil? ? Attrs.empty : attrs
        raise ArgumentError, 'attrs must be SST::Attrs' unless attrs_value.is_a?(Attrs)

        attrs_value
      end
      private_class_method :coerce_attrs

      def self.coerce_children(children)
        kids = Array(children).freeze
        raise ArgumentError, 'children must be SST::Node instances' unless kids.all?(Node)

        kids
      end
      private_class_method :coerce_children

      ##
      # @return [Boolean]
      def link?
        name == :a && eligible_href?
      end

      ##
      # @return [Boolean]
      def image? = name == :img

      ##
      # @return [Boolean]
      def heading? = Tags::HEADING_NAMES.include?(name)

      ##
      # @return [Boolean]
      def utility_landmark? = Tags::UTILITY_LANDMARK_NAMES.include?(name)

      ##
      # @return [Boolean]
      def ignored_container_name? = Tags::IGNORED_CONTAINER_NAMES.include?(name)

      ##
      # @return [Boolean]
      def eligible_href?
        href = attrs.href
        return false if href.nil? || href.empty?

        Tags::SKIP_HREF_PREFIXES.none? { |prefix| href.start_with?(prefix) }
      end

      ##
      # Depth-first enumeration of self and descendants.
      #
      # @yieldparam node [Node]
      # @return [Enumerator, Array<Node>]
      def each_node(&block)
        return enum_for(:each_node) unless block

        yield self
        children.each { |child| child.each_node(&block) }
      end

      ##
      # @return [Array<Node>] all descendants excluding self
      def descendants
        children.flat_map { |child| [child, *child.descendants] }
      end

      ##
      # @return [Array<Node>]
      def find_all(&predicate)
        each_node.select(&predicate)
      end

      ##
      # @return [Node, nil]
      def find(&predicate)
        each_node.find(&predicate)
      end

      ##
      # Visible text with block newlines, excluding optional subtrees.
      #
      # @param separator [String]
      # @param exclude [Array<Node>, nil]
      # @return [String, nil]
      def visible_text(separator: ' ', exclude: nil)
        Html::SstText.extract(self, separator:, exclude:)
      end

      ##
      # @return [Integer] alphanumeric word count of visible text
      def word_count
        visible_text.to_s.scan(/\p{Alnum}+/).size
      end

      ##
      # @return [Float] words per descendant link
      def text_density
        words = word_count
        links = descendants.count(&:link?)
        links.zero? ? words.to_f : words.to_f / links
      end
    end
  end
end
