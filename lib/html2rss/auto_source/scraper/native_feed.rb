# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      ##
      # Promotes a page's native RSS/Atom feed via {Syndication::Discovery} + {Syndication::Parser}.
      # After {#each}, {#channel} holds what that feed states about its channel and {#feed_url} where
      # it was read, the provenance {Cleanup} admits the feed's own domain by.
      class NativeFeed
        include Enumerable

        # Href shapes that Discovery's path probing can still resolve when the link type is not a feed MIME type.
        FEEDISH_HREF = /rss|atom|feed|\.xml/i
        private_constant :FEEDISH_HREF

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
          return false unless parsed_body.is_a?(Nokogiri::HTML::Document)

          return true if Html2rss::Html::FeedLink.from_document(parsed_body).any?

          parsed_body.css('head link[rel~="alternate"][href]').any? { |node| node['href'].match?(FEEDISH_HREF) }
        end

        ##
        # @param parsed_body [Nokogiri::HTML::Document]
        # @param url [String, Html2rss::Url]
        # @param request_session [Html2rss::RequestSession, nil]
        def initialize(parsed_body, url:, request_session: nil)
          @parsed_body = parsed_body
          @url = Html2rss::Url.from_absolute(url)
          @request_session = request_session
        end

        # @return [Boolean]
        def extractable? = self.class.articles?(parsed_body)

        ##
        # @return [Syndication::ChannelFacts, nil] what the followed feed states about its channel;
        #   nil before {#each} or when no feed was read
        def channel = @feed&.channel

        ##
        # @return [Html2rss::Url, nil] URL of the feed read (after redirects); nil before {#each} or
        #   when no feed was read
        attr_reader :feed_url

        ##
        # @yieldparam article [Hash{Symbol => Object}]
        # @return [Enumerator, void]
        # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength -- structured empty/items logs
        def each(&)
          return enum_for(:each) unless block_given?

          articles = (@feed = fetch_feed).articles
          if articles.empty?
            Log.info({
              event_name: 'auto_source.native_feed.empty',
              host: url.host,
              message: "#{self.class}: host=#{url.host} item_count=0 fallback=true"
            }.to_json)
            return
          end

          Log.info({
            event_name: 'auto_source.native_feed.items',
            host: url.host,
            message: "#{self.class}: host=#{url.host} item_count=#{articles.size} fallback=false"
          }.to_json)
          articles.each(&)
        end

        private

        attr_reader :parsed_body, :url, :request_session

        # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength -- discovery + parse + structured warn
        def fetch_feed
          return Syndication::Feed::NONE unless request_session

          response = Syndication::Discovery.best_feed_response(
            page_url: url,
            request_session:,
            parsed_body:,
            max_probes: self.class.request_slots
          )
          return Syndication::Feed::NONE unless response

          @feed_url = response.url
          Syndication::Parser.parse_response(response)
        rescue Html2rss::Error => error
          Log.warn({
            event_name: 'auto_source.native_feed.failed',
            host: url.host,
            error_class: error.class.name,
            message: "#{self.class}: host=#{url.host} failed (#{error.class}: #{error.message})"
          }.to_json)
          Syndication::Feed::NONE
        end
      end
    end
  end
end
