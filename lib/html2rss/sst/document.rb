# frozen_string_literal: true

module Html2rss
  module SST
    ##
    # Immutable SST document: root node plus relationship index.
    Document = Data.define(:root, :index, :degraded, :node_count) do
      ##
      # @param root [Node]
      # @param index [Index]
      # @param degraded [Boolean] true when MAX_NODES forced semantic-tag-only mode
      # @param node_count [Integer]
      # @return [Document]
      # @raise [ArgumentError] when root/index missing
      def self.build(root:, index:, degraded: false, node_count: 0)
        raise ArgumentError, 'root is required' unless root.is_a?(Node)
        raise ArgumentError, 'index is required' unless index.is_a?(Index)

        new(root:, index:, degraded: !!degraded, node_count: Integer(node_count))
      end
    end
  end
end
