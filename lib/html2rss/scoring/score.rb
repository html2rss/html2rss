# frozen_string_literal: true

module Html2rss
  module Scoring
    ##
    # Composite score with quality/junk split and optional typed feature breakdown.
    Score = Data.define(:composite, :quality, :junk, :breakdown) do
      ##
      # @param composite [Numeric]
      # @param quality [Numeric, nil]
      # @param junk [Numeric, nil]
      # @param breakdown [Hash{Symbol => Numeric}, nil]
      # @return [Score]
      # @raise [ArgumentError] when composite is not numeric
      def self.build(composite:, quality: nil, junk: nil, breakdown: nil)
        raise ArgumentError, 'composite must be Numeric' unless composite.is_a?(Numeric)

        parts = if breakdown.nil?
                  Score::EMPTY_BREAKDOWN
                else
                  breakdown.transform_keys { FeatureId.assert!(_1) }.freeze
                end

        new(
          composite: composite.to_f,
          quality: (quality.nil? ? composite : quality).to_f,
          junk: (junk || 0).to_f,
          breakdown: parts
        )
      end
    end
    Score::EMPTY_BREAKDOWN = {}.freeze
  end
end
