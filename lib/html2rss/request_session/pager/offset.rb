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
          param = config.fetch(:param, DEFAULT_PARAM)
          url = Html2rss::Url.from_absolute(page_response.url)
          url.with_query_values(url.query_values.merge(param.to_s => target_offset_for(page_number).to_s))
        end

        # @param page_number [Integer]
        # @return [Integer]
        def target_offset_for(page_number)
          start_offset = config.fetch(:start_offset, DEFAULT_START_OFFSET)
          increment = config.fetch(:increment, DEFAULT_INCREMENT)
          start_offset + ((page_number - 1) * increment)
        end
      end
    end
  end
end
