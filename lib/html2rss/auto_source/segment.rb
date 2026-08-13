# frozen_string_literal: true

module Html2rss
  class AutoSource
    ##
    # One candidate content block discovered by {Segmenter}.
    Segment = Data.define(:root_node, :primary_link, :strategy, :position) do
      ##
      # @param root_node [SST::Node]
      # @param primary_link [SST::Node, nil]
      # @param strategy [Symbol]
      # @param position [Integer]
      # @return [Segment]
      # @raise [ArgumentError] on invalid construction
      def self.build(root_node:, primary_link: nil, strategy:, position:)
        raise ArgumentError, 'root_node must be SST::Node' unless root_node.is_a?(SST::Node)
        raise ArgumentError, 'primary_link must be SST::Node or nil' unless primary_link.nil? || primary_link.is_a?(SST::Node)
        raise ArgumentError, "unknown strategy: #{strategy.inspect}" unless Segment::STRATEGIES.include?(strategy)
        raise ArgumentError, 'position must be Integer' unless position.is_a?(Integer)

        new(root_node:, primary_link:, strategy:, position:)
      end
    end
    Segment::STRATEGIES = %i[semantic list cluster].to_set.freeze
  end
end
