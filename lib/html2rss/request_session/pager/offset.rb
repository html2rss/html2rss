# frozen_string_literal: true

module Html2rss
  class RequestSession
    module Pager
      ##
      # Paginate using numeric offset increments in query parameters or URL path templates.
      class Offset < Base
        # Default query parameter name for offset pagination.
        # @return [String]
        DEFAULT_PARAM = 'offset'

        # Default starting numeric offset value.
        # @return [Integer]
        DEFAULT_START_OFFSET = 0

        # Default offset increment per page.
        # @return [Integer]
        DEFAULT_INCREMENT = 20

        private

        # @param page_response [RequestService::Response]
        # @param page_number [Integer]
        # @return [Html2rss::Url]
        def next_page_url(page_response, page_number:)
          stepped_url(page_response, page_number:, param: config.fetch(:param, DEFAULT_PARAM),
                                     start: config.fetch(:start_offset, DEFAULT_START_OFFSET),
                                     step: config.fetch(:increment, DEFAULT_INCREMENT))
        end
      end
    end
  end
end
