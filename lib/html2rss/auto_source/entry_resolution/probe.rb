# frozen_string_literal: true

module Html2rss
  class AutoSource
    module EntryResolution
      ##
      # Cheap follow-up probe that scores a candidate via {PageRecon.assess} or syndication parse.
      class Probe
        ##
        # @param url [Html2rss::Url]
        # @param score [Numeric]
        # @param articles_count [Integer]
        # @param response [Html2rss::RequestService::Response] the fetched candidate (reused when it wins)
        Scored = Data.define(:url, :score, :articles_count, :response)

        ##
        # @param request_session [Html2rss::RequestSession]
        # @param origin_url [String, Html2rss::Url]
        # @param channel [Hash{Symbol => Object}] channel overrides; an explicit +:language+ applies to every candidate
        def initialize(request_session:, origin_url:, channel: {})
          @channel = channel
          @request_session = request_session
          @origin_url = Url.from_absolute(origin_url)
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
          score_response(response)
        rescue Html2rss::ContractError
          raise
        rescue Html2rss::Error
          nil
        end

        private

        attr_reader :request_session, :origin_url, :channel

        def score_response(response) # rubocop:disable Metrics/MethodLength -- feed vs HTML branches
          if response.feed_response?
            count = Syndication::Parser.parse_response(response).articles.size
            return Scored.new(
              url: response.url,
              score: Scorer.score_feed(articles_count: count),
              articles_count: count,
              response:
            )
          end

          assessment = PageRecon.assess(response:, url: response.url, channel:)
          Scored.new(
            url: response.url,
            score: Scorer.score_assessment(assessment),
            articles_count: assessment.articles_count,
            response:
          )
        end
      end
    end
  end
end
