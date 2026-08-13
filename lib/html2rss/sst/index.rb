# frozen_string_literal: true

module Html2rss
  module SST
    ##
    # Parent/depth indices for an SST tree. Built once by the Normalizer so
    # Scoring/Segmenter never need Nokogiri ancestor walks.
    class Index
      ##
      # @param root [Node]
      # @param parents [Hash{Node => Node, nil}]
      # @param depths [Hash{Node => Integer}]
      # @param ignored_chrome [Hash{Node => Boolean}]
      def initialize(root:, parents:, depths:, ignored_chrome:)
        @root = root
        @parents = parents
        @depths = depths
        @ignored_chrome = ignored_chrome
      end

      attr_reader :root

      ##
      # @param node [Node]
      # @return [Node, nil]
      def parent_of(node) = @parents[node]

      ##
      # @param node [Node]
      # @return [Integer]
      def depth_of(node) = @depths.fetch(node, 0)

      ##
      # @param node [Node]
      # @return [Boolean]
      def ignored_chrome?(node) = @ignored_chrome.fetch(node, false)

      ##
      # @param child [Node]
      # @param ancestor [Node]
      # @return [Boolean]
      def descendant_of?(child, ancestor)
        curr = parent_of(child)
        while curr
          return true if curr.equal?(ancestor)

          curr = parent_of(curr)
        end
        false
      end

      ##
      # @param node [Node]
      # @param condition [#call]
      # @return [Node, nil]
      def parent_until(node, condition)
        curr = node
        while curr && curr.name != :html
          return curr if condition.call(curr)

          curr = parent_of(curr)
        end
        nil
      end

      ##
      # @yieldparam node [Node]
      # @return [Enumerator]
      def each_node(&)
        root.each_node(&)
      end
    end
  end
end
