# frozen_string_literal: true

module Html2rss
  module SST
    Document = Data.define(:root, :index, :degraded, :node_count)

    ##
    # Immutable SST document: root node plus relationship index.
    class Document
      ##
      # @param root [Node]
      # @param index [Index]
      # @param degraded [Boolean] true when MAX_NODES forced semantic-tag-only mode
      # @param node_count [Integer]
      # @return [Document]
      # @raise [InvalidError] when root/index missing
      def self.build(root:, index:, degraded: false, node_count: 0)
        raise InvalidError, 'root is required' unless root.is_a?(Node)
        raise InvalidError, 'index is required' unless index.is_a?(Index)

        new(root:, index:, degraded: !!degraded, node_count: Integer(node_count))
      end
    end
  end
end
