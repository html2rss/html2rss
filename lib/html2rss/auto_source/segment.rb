# frozen_string_literal: true

module Html2rss
  class AutoSource
    Segment = Data.define(:root_node, :primary_link, :strategy, :position)

    ##
    # One candidate content block discovered by {Segmenter}.
    class Segment
      # Raised when a segment (or the Segmenter producing segments) gets invalid input.
      class InvalidError < Html2rss::Error; end

      # Allowed Segmenter strategies.
      STRATEGIES = Set[:semantic, :list, :cluster].freeze

      ##
      # @param root_node [SST::Node]
      # @param primary_link [SST::Node, nil]
      # @param strategy [Symbol]
      # @param position [Integer]
      # @return [Segment]
      # @raise [InvalidError] on invalid construction
      def self.build(root_node:, strategy:, position:, primary_link: nil)
        raise InvalidError, 'root_node must be SST::Node' unless root_node.is_a?(SST::Node)
        unless primary_link.nil? || primary_link.is_a?(SST::Node)
          raise InvalidError, 'primary_link must be SST::Node or nil'
        end

        strategy!(strategy)
        raise InvalidError, 'position must be Integer' unless position.is_a?(Integer)

        new(root_node:, primary_link:, strategy:, position:)
      end

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
