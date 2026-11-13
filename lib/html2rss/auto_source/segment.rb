# frozen_string_literal: true

module Html2rss
  class AutoSource
    Segment = Data.define(:root_node, :primary_link, :strategy, :position, :group_size)

    ##
    # One candidate content block discovered by {Segmenter}.
    class Segment
      # Raised when a segment (or the Segmenter producing segments) gets invalid input.
      class InvalidError < Html2rss::ContractError; end

      # Allowed Segmenter strategies.
      STRATEGIES = Set[:semantic, :list, :cluster].freeze

      ##
      # @param root_node [SST::Node]
      # @param primary_link [SST::Node, nil]
      # @param strategy [Symbol]
      # @param position [Integer]
      # @param group_size [Integer] how many segments of the run share this one's structural path
      #   (the repeated-card group it belongs to; 1 when it stands alone)
      # @return [Segment]
      # @raise [InvalidError] on invalid construction
      def self.build(root_node:, strategy:, position:, primary_link: nil, group_size: 1)
        raise InvalidError, 'root_node must be SST::Node' unless root_node.is_a?(SST::Node)
        unless primary_link.nil? || primary_link.is_a?(SST::Node)
          raise InvalidError, 'primary_link must be SST::Node or nil'
        end

        strategy!(strategy)
        raise InvalidError, 'position must be Integer' unless position.is_a?(Integer)
        raise InvalidError, 'group_size must be a positive Integer' unless positive_integer?(group_size)

        new(root_node:, primary_link:, strategy:, position:, group_size:)
      end

      def self.positive_integer?(value) = value.is_a?(Integer) && value.positive?
      private_class_method :positive_integer?

      ##
      # @param strategy [Symbol]
      # @return [Symbol] +strategy+ when it is one of {STRATEGIES}
      # @raise [InvalidError] for any other value
      def self.strategy!(strategy)
        return strategy if STRATEGIES.include?(strategy)

        raise InvalidError, "unknown strategy: #{strategy.inspect}"
      end
    end
  end
end
