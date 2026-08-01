# frozen_string_literal: true

require 'uri'

module Html2rss
  class RequestSession
    module Pager
      ##
      # Abstract base class for pagination strategies.
      class Base
        include Enumerable

        DEFAULT_MAX_PAGES = 5

        # @param session [RequestSession] request session used to execute follow-ups
        # @param initial_response [RequestService::Response] first page response
        # @param config [Hash, Integer] pagination configuration or max_pages integer
        # @param logger [Logger] logger used for pagination stop warnings
        def initialize(session:, initial_response:, config: {}, logger: Html2rss::Log)
          @session = session
          @initial_response = initial_response
          @config = config.is_a?(Hash) ? config : { max_pages: config }
          @logger = logger
        end

        # @yield [RequestService::Response] each page response
        # @return [Enumerator] enumerator when no block is given
        def each
          return enum_for(:each) unless block_given?

          yield initial_response

          current_response = initial_response
          session.effective_page_budget(max_pages).pred.times do |index|
            next_url = next_page_url(current_response, page_number: index + 2)
            break unless follow_up_allowed?(next_url)

            current_response = fetch_follow_up_response_or_stop(next_url, current_response.url)
            break unless current_response

            yield current_response
          end
        end

        private

        attr_reader :session, :initial_response, :config, :logger

        # @return [Integer] configured maximum pages
        def max_pages
          config.fetch(:max_pages, DEFAULT_MAX_PAGES)
        end

        # @param next_url [String, URI, nil]
        # @return [Boolean]
        def follow_up_allowed?(next_url)
          !next_url.nil? && !next_url.to_s.empty? && !session.visited?(next_url)
        end

        # @param next_url [String, URI]
        # @param origin_url [String, URI]
        # @return [RequestService::Response, nil]
        def fetch_follow_up_response_or_stop(next_url, origin_url)
          session.follow_up(url: next_url, relation: :pagination, origin_url:)
        rescue RequestService::RequestBudgetExceeded => error
          logger.warn(
            "#{self.class}: pagination stopped at #{next_url} - #{error.message}. " \
            "Retry with --max-requests #{session.max_requests + 1} or increase request.max_requests in the config."
          )
          nil
        end

        # @param url_str [String]
        # @param param_name [String, Symbol]
        # @param param_val [Object]
        # @return [String]
        def build_url_with_param(url_str, param_name, param_val)
          uri = URI.parse(url_str.to_s)
          params = URI.decode_www_form(uri.query || '')
          params.reject! { |k, _| k == param_name.to_s }
          params << [param_name.to_s, param_val.to_s]
          uri.query = URI.encode_www_form(params)
          uri.to_s
        end

        # @param page_response [RequestService::Response]
        # @param page_number [Integer] 1-based target page number (e.g. 2 for second page)
        # @return [String, URI, nil]
        def next_page_url(page_response, page_number:)
          raise NotImplementedError, "#{self.class}#next_page_url must be implemented by subclass"
        end
      end
    end
  end
end
