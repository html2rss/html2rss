# frozen_string_literal: true

module Html2rss
  class RequestSession
    module Pager
      ##
      # Paginate using page number increments in query parameters or URL path templates.
      class UrlTemplate < Base
        # Default query parameter name for page number pagination.
        # @return [String]
        DEFAULT_PARAM = 'page'

        # Default starting page number.
        # @return [Integer]
        DEFAULT_START_PAGE = 1

        # Default page number step increment.
        # @return [Integer]
        DEFAULT_STEP = 1

        private

        # @param page_response [RequestService::Response]
        # @param page_number [Integer] 1-based target page number (e.g. 2 for 2nd page)
        # @return [Html2rss::Url]
        def next_page_url(page_response, page_number:)
          stepped_url(page_response, page_number:, param: config.fetch(:param, DEFAULT_PARAM),
                                     start: config.fetch(:start_page, DEFAULT_START_PAGE),
                                     step: config.fetch(:step, DEFAULT_STEP))
        end
      end
    end
  end
end
