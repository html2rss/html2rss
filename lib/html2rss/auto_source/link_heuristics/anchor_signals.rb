# frozen_string_literal: true

module Html2rss
  class AutoSource
    class LinkHeuristics
      # Score weights keyed by AnchorSignals member name.
      ANCHOR_SCORE_RULES = {
        heading_anchor: 100,
        heading_text_match: 20,
        meaningful_text: 10,
        content_like_destination: 10
      }.freeze

      # Anchor ranking signals used by semantic primary-link selection.
      AnchorSignals = Data.define(
        :heading_anchor,
        :heading_text_match,
        :meaningful_text,
        :content_like_destination
      ) do
        # @return [Integer] ranking score for one eligible anchor
        def score
          ANCHOR_SCORE_RULES.sum { |signal, weight| public_send(signal) ? weight : 0 }
        end
      end
    end
  end
end
