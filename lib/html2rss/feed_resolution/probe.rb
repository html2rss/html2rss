# frozen_string_literal: true

module Html2rss
  module FeedResolution
    ##
    # Cheap follow-up probe that scores a candidate via {PageRecon} or syndication parse.
    class Probe
      # Weight for admitted article counts on HTML probes.
      ARTICLE_WEIGHT = 10
      # Bonus when the surface looks like a listing rather than a hub/shell.
      LISTING_SURFACE_BONUS = 5
      # Surfaces that indicate the candidate is still a weak hub.
      WEAK_SURFACES = Policy::WEAK_SURFACES

      ##
      # @param url [Html2rss::Url]
      # @param score [Numeric]
      # @param articles_count [Integer]
      Scored = Data.define(:url, :score, :articles_count)

      ##
      # @param request_session [Html2rss::RequestSession]
      # @param origin_url [String, Html2rss::Url]
      def initialize(request_session:, origin_url:)
        @request_session = request_session
        @origin_url = Html2rss::Url.from_absolute(origin_url)
      end

      ##
      # @param url [Html2rss::Url]
      # @return [Scored, nil]
      def call(url)
        response = request_session.follow_up(
          url:,
          relation: :entry_resolution,
          origin_url:
        )
        score_response(url, response)
      rescue Html2rss::Error
        nil
      end

      private

      attr_reader :request_session, :origin_url

      def score_response(url, response)
        if response.feed_response?
          count = Syndication::Parser.parse_response(response).size
          return Scored.new(url: response.url, score: count * ARTICLE_WEIGHT, articles_count: count)
        end

        recon = PageRecon.call(response:, url:)
        Scored.new(url: response.url, score: score_recon(recon), articles_count: recon.articles_count)
      end

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
