# frozen_string_literal: true

require 'json'

module Html2rss
  class RequestSession
    module Pager
      ##
      # Digs into JSON response payloads to extract next page URLs or cursor tokens.
      class JsonCursor < Base
        # Default query parameter name for cursor token pagination.
        # @return [String]
        DEFAULT_PARAM = 'cursor'

        private

        # @param page_response [RequestService::Response]
        # @param page_number [Integer]
        # @return [String, nil]
        def next_page_url(page_response, page_number: nil) # rubocop:disable Lint/UnusedMethodArgument
          json_data = parse_json_body(page_response)
          return nil unless json_data

          url_from_next_path(json_data, page_response.url) ||
            url_from_cursor_path(json_data, page_response.url)
        end

        # @param json_data [Hash]
        # @param origin_url [Html2rss::Url]
        # @return [String, nil]
        def url_from_next_path(json_data, origin_url)
          return nil unless (next_url_path = config[:next_url_path])

          next_url = dig_path(json_data, next_url_path)
          Html2rss::Url.from_relative(next_url.to_s, origin_url) if next_url && !next_url.to_s.empty?
        end

        # @param json_data [Hash]
        # @param origin_url [Html2rss::Url]
        # @return [Html2rss::Url, nil]
        def url_from_cursor_path(json_data, origin_url)
          return nil unless (cursor_path = config[:cursor_path])

          cursor_val = dig_path(json_data, cursor_path)
          return nil if cursor_val.nil? || cursor_val.to_s.empty?

          param = config.fetch(:param, DEFAULT_PARAM)
          url = Html2rss::Url.from_absolute(origin_url)
          url.with_query_values(url.query_values.merge(param.to_s => cursor_val.to_s))
        end

        # @param page_response [RequestService::Response]
        # @return [Hash, nil]
        def parse_json_body(page_response)
          JSON.parse(page_response.body)
        rescue JSON::ParserError
          nil
        end

        # @param hash [Hash]
        # @param path [String, Symbol]
        # @return [Object, nil]
        def dig_path(hash, path)
          return nil unless hash.is_a?(Hash)

          keys = path.to_s.split('.')
          result = hash
          keys.each do |key|
            return nil unless result.is_a?(Hash)

            result = result[key] || result[key.to_sym]
          end
          result
        end
      end
    end
  end
end
