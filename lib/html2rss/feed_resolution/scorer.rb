# frozen_string_literal: true

module Html2rss
  module FeedResolution
    ##
    # Scores probe targets from cheap {PageRecon} facts or syndication item counts.
    module Scorer
      # Weight for admitted article counts on HTML probes.
      ARTICLE_WEIGHT = 10
      # Bonus when the surface looks like a listing rather than a hub/shell.
      LISTING_SURFACE_BONUS = 5
      # Surfaces that indicate the candidate is still a weak hub.
      WEAK_SURFACES = Policy::WEAK_SURFACES

      module_function

      ##
      # @param articles_count [Integer]
      # @return [Integer]
      def score_feed(articles_count:)
        articles_count.to_i * ARTICLE_WEIGHT
      end

      ##
      # @param recon [Html2rss::PageRecon::Result]
      # @return [Integer]
      def score_recon(recon)
        score = recon.articles_count * ARTICLE_WEIGHT
        score += LISTING_SURFACE_BONUS unless WEAK_SURFACES.include?(recon.surface_category)
        drops = recon.admission_drops.values.sum
        total = recon.articles_count + drops
        score -= ((drops.to_f / total) * ARTICLE_WEIGHT).round if total.positive?
        score
      end
    end
  end
end
