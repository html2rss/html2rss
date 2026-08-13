# frozen_string_literal: true

module Html2rss
  module Scoring
    ##
    # Primary-link ranking weights (sole home; FeatureId-aligned).
    module AnchorScore
      # Signal → integer weight map for primary-link ranking.
      WEIGHTS = {
        heading_anchor: 100,
        heading_text_match: 20,
        meaningful_text: 10,
        content_like_destination: 10
      }.freeze

      module_function

      ##
      # @param heading_anchor [Boolean]
      # @param heading_text_match [Boolean]
      # @param meaningful_text [Boolean]
      # @param content_like_destination [Boolean]
      # @return [Integer]
      def score(heading_anchor:, heading_text_match:, meaningful_text:, content_like_destination:)
        total = 0
        total += WEIGHTS[:heading_anchor] if heading_anchor
        total += WEIGHTS[:heading_text_match] if heading_text_match
        total += WEIGHTS[:meaningful_text] if meaningful_text
        total += WEIGHTS[:content_like_destination] if content_like_destination
        total
      end
    end
  end
end
