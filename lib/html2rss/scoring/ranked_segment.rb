# frozen_string_literal: true

module Html2rss
  module Scoring
    ##
    # A segment paired with its composite score.
    RankedSegment = Data.define(:segment, :score) do
      ##
      # @return [SST::Node]
      def root_node = segment.root_node

      ##
      # @return [SST::Node, nil]
      def primary_link = segment.primary_link

      ##
      # @return [Float]
      def final_score = score.composite

      ##
      # @return [Float]
      def quality_score = score.quality

      ##
      # @return [Float]
      def junk_score = score.junk

      ##
      # @return [Integer]
      def position = segment.position
    end
  end
end
