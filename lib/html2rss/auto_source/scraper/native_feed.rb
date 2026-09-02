# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      ##
      # Promotes a page's native RSS/Atom feed via {Syndication::Discovery} + {Syndication::Parser}.
      class NativeFeed
        include Enumerable

        # @return [Symbol] scraper config key
        def self.options_key = :native_feed

        ##
        # @param _opts [Hash] unused options
        # @return [Integer] follow-up request slots (discovery probes + feed fetch share the budget)
        def self.request_slots(_opts = {})
          1
        end

        ##
        # Shallow claim: head advertises a syndication alternate, or body looks feed-capable
        # enough that path discovery is worth a follow-up slot.
        #
        # @param parsed_body [Nokogiri::HTML::Document, nil]
        # @return [Boolean]
        def self.articles?(parsed_body)
          return false unless ::Html2rss::Html::Document.html_document?(parsed_body)

          return true if ::Html2rss::Html::FeedLink.from_document(parsed_body).any?

          parsed_body.css('head link[rel~="alternate"][href]').any? do |node|
            href = node['href'].to_s
            ::Html2rss::Html::Probe.mime_match?(
              node['type'],
              ::Html2rss::Html::Probe::APPLICATION_RSS_XML,
              ::Html2rss::Html::Probe::APPLICATION_ATOM_XML
            ) || href.match?(/rss|atom|feed|\.xml/i)
          end
        end

        ##
        # @param parsed_body [Nokogiri::HTML::Document]
        # @param url [String, Html2rss::Url]
        # @param request_session [Html2rss::RequestSession, nil]
        # @param _opts [Hash]
        # @option _opts [Object] :_reserved reserved for future scraper-specific options
        def initialize(parsed_body, url:, request_session: nil, **_opts)
          @parsed_body = parsed_body
          @url = Html2rss::Url.from_absolute(url)
          @request_session = request_session
        end

        ##
        # @yieldparam article [Hash{Symbol => Object}]
        # @return [Enumerator, void]
        def each(&)
          return enum_for(:each) unless block_given?

          articles = fetch_articles
          if articles.empty?
            Log.info("#{self.class}: host=#{url.host} item_count=0 fallback=true")
            return
          end

          Log.info("#{self.class}: host=#{url.host} item_count=#{articles.size} fallback=false")
          articles.each(&)
        end

        private

        attr_reader :parsed_body, :url, :request_session

        def fetch_articles # rubocop:disable Metrics/MethodLength -- discovery + parse path
          return [] unless request_session

          response = Syndication::Discovery.best_feed_response(
            page_url: url,
            request_session:,
            parsed_body:,
            max_probes: self.class.request_slots
          )
          return [] unless response

          Syndication::Parser.parse_response(response)
        rescue Html2rss::Error, ArgumentError => error
          Log.warn("#{self.class}: host=#{url.host} failed (#{error.class}: #{error.message})")
          []
        end
      end
    end
  end
end
