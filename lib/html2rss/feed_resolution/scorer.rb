# frozen_string_literal: true

module Html2rss
  module FeedResolution
    ##
    # Scores probe targets and picks winners from cheap {PageRecon::Assessment} facts
    # or syndication item counts.
    module Scorer
      # Weight for admitted article counts on HTML probes.
      ARTICLE_WEIGHT = 10
      # Bonus when the surface looks like a listing rather than a hub/shell.
      LISTING_SURFACE_BONUS = 5

      module_function

      ##
      # @param articles_count [Integer]
      # @return [Integer]
      def score_feed(articles_count:)
        articles_count.to_i * ARTICLE_WEIGHT
      end

      ##
      # @param assessment [Html2rss::PageRecon::Assessment]
      # @return [Integer]
      def score_assessment(assessment)
        score = assessment.articles_count * ARTICLE_WEIGHT
        score += LISTING_SURFACE_BONUS if assessment.listing_bonus?
        drops = assessment.admission_drops.values.sum
        total = assessment.articles_count + drops
        score -= ((drops.to_f / total) * ARTICLE_WEIGHT).round if total.positive?
        score
      end

      ##
      # @param scored [Array<Probe::Scored>]
      # @param entry_articles_count [Integer]
      # @return [Probe::Scored, nil]
      def pick_winner(scored:, entry_articles_count:)
        winner = scored.max_by(&:score)
        return unless winner
        return if winner.articles_count <= entry_articles_count.to_i
        return if winner.score <= 0

        winner
      end
    end
  end
end
