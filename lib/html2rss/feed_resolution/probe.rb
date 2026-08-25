# frozen_string_literal: true

module Html2rss
  module FeedResolution
    ##
    # Cheap follow-up probe that scores a candidate via {PageRecon.assess} or syndication parse.
    class Probe
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

      def score_response(_url, response) # rubocop:disable Metrics/MethodLength -- feed vs HTML branches
        if response.feed_response?
          count = Syndication::Parser.parse_response(response).size
          return Scored.new(
            url: response.url,
            score: Scorer.score_feed(articles_count: count),
            articles_count: count
          )
        end

        assessment = PageRecon.assess(response:, url: response.url)
        Scored.new(
          url: response.url,
          score: Scorer.score_assessment(assessment),
          articles_count: assessment.articles_count
        )
      end
    end
  end
end
