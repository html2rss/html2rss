# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      Context = Data.define(:parsed_body, :opts, :url, :request_session, :body, :document, :link_resolver,
                            :time_zone, :captured_responses)

      ##
      # What one page offers a scraper at construction: the parsed page, the full scraper options map (+opts+)
      # and the shared page state that {Scraper.build_instance} hands only to the scrapers that read it.
      # +document+ is the SST document, set for the heuristic tiers only; +captured_responses+ are
      # browser-captured JSON XHR/fetch bodies; +time_zone+ is the channel's, for naive leftover dates.
      class Context
        # Optional fields and their defaults.
        PAGE_STATE = { request_session: nil, body: nil, document: nil, link_resolver: nil, time_zone: nil,
                       captured_responses: [].freeze }.freeze

        ##
        # @param parsed_body [Nokogiri::HTML::Document]
        # @param opts [Hash]
        # @param url [Html2rss::Url, String]
        # @param page_state [Hash] any other field; the rest default to {PAGE_STATE}
        # @option page_state [Html2rss::RequestSession, nil] :request_session
        # @option page_state [String, nil] :body raw response body
        # @option page_state [Html2rss::Html::SST::Document, nil] :document
        # @option page_state [Scoring::LinkResolver, nil] :link_resolver
        # @option page_state [String, nil] :time_zone
        # @option page_state [Array<Hash>] :captured_responses
        def initialize(parsed_body:, opts:, url:, **page_state)
          super(parsed_body:, opts:, url:, **PAGE_STATE, **page_state)
        end
      end
    end
  end
end
