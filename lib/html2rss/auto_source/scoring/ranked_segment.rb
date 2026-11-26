# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scoring
      RankedSegment = Data.define(:segment, :score)

      ##
      # A segment paired with its composite score.
      class RankedSegment
        ##
        # @return [Html::SST::Node]
        def root_node = segment.root_node

        ##
        # @return [Html::SST::Node, nil]
        def primary_link = segment.primary_link

        ##
        # @return [Float]
        def final_score = score.composite

        ##
        # @return [Float]
        def quality_score = score.quality

        ##
        # @return [Integer]
        def position = segment.position
      end
    end
  end
end
