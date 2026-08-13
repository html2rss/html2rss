# frozen_string_literal: true

module Html2rss
  module Scoring
    ##
    # A segment paired with its composite score.
    RankedSegment = Data.define(:segment, :score) do
      ##
      # @param segment [Html2rss::AutoSource::Segment]
      # @param score [Score]
      # @return [RankedSegment]
      # @raise [ArgumentError] on invalid types
      def self.build(segment:, score:)
        raise ArgumentError, 'segment must be AutoSource::Segment' unless segment.is_a?(Html2rss::AutoSource::Segment)
        raise ArgumentError, 'score must be Scoring::Score' unless score.is_a?(Score)

        new(segment:, score:)
      end

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
