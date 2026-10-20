# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      # Extracts articles from a parsed JSON response body (Hash or Array).
      # JSON Feed documents map item fields directly; every other document walks
      # via {JsonState.discover_articles}. Does not scan HTML.
      class JsonDocument
        include Enumerable

        # Substring that identifies a JSON Feed +version+ URL.
        JSON_FEED_VERSION_MARKER = 'jsonfeed.org'

        # @return [Symbol] scraper config key
        def self.options_key = :json_document

        # @param _opts [Hash] unused scraper options
        # @return [Integer] zero — no additional HTTP requests
        def self.request_slots(_opts = {}) = 0

        # Not detectable from HTML alone; instance {#extractable?} requires a
        # Hash or Array body (wired by AutoSource for JSON responses).
        #
        # @param _parsed_body [Object] unused
        # @return [Boolean]
        def self.articles?(_parsed_body) = false

        # @param parsed_body [Hash, Array, Object] parsed JSON document (or HTML when misrouted)
        # @param url [String, Html2rss::Url] base URL for relative link resolution
        # @param _opts [Hash] scraper-specific options
        # @option _opts [Object] :_reserved reserved for future scraper-specific options
        def initialize(parsed_body, url:, **_opts)
          @parsed_body = parsed_body
          @url = url
        end

        # @return [Boolean] true when +parsed_body+ is a Hash or Array
        def extractable?
          @parsed_body.is_a?(Hash) || @parsed_body.is_a?(Array)
        end

        # @yield [Hash{Symbol => Object}] normalized article hash
        # @return [Enumerator, void] article enumerator when no block is given
        def each(&block)
          return enum_for(:each) unless block
          return unless extractable?

          if json_feed?
            each_json_feed_item(&block)
          else
            JsonState.discover_articles(@parsed_body, base_url: @url) do |article|
              yield(article) if article
            end
          end
        end

        private

        def json_feed?
          return false unless @parsed_body.is_a?(Hash)

          version = @parsed_body[:version].to_s
          version.include?(JSON_FEED_VERSION_MARKER) && @parsed_body[:items].is_a?(Array)
        end

        def each_json_feed_item
          @parsed_body[:items].each do |item|
            article = map_json_feed_item(item)
            yield article if article
          end
        end

        def map_json_feed_item(item)
          return unless item.is_a?(Hash)

          article_url = resolve_json_feed_url(item)
          return unless article_url

          json_feed_article_hash(item, article_url)
        end

        def json_feed_article_hash(item, article_url)
          {
            title: string(item[:title]),
            description: json_feed_description(item),
            url: article_url,
            image: resolve_optional_url(item[:image]),
            published_at: string(item[:date_published]),
            categories: json_feed_tags(item[:tags]),
            id: string(item[:id]) || article_url.to_s
          }.compact
        end

        def resolve_json_feed_url(item)
          resolve_optional_url(item[:url]) || absolute_url(item[:id])
        end

        def resolve_optional_url(value)
          str = string(value)
          return unless str

          Url.from_relative(str, @url)
        rescue ArgumentError
          nil
        end

        def absolute_url(value)
          str = string(value)
          return unless str

          Url.from_absolute(str)
        rescue ArgumentError
          nil
        end

        def json_feed_description(item)
          string(item[:content_text]) || string(item[:content_html])
        end

        def json_feed_tags(tags)
          return unless tags.is_a?(Array)

          names = tags.filter_map { |tag| string(tag) }
          names.uniq!
          names unless names.empty?
        end

        def string(value)
          trimmed = value.to_s.strip
          trimmed unless trimmed.empty?
        end
      end
    end
  end
end
