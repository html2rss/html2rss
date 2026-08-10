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
          param = config.fetch(:param, DEFAULT_PARAM)
          start_page = config.fetch(:start_page, DEFAULT_START_PAGE)
          step = config.fetch(:step, DEFAULT_STEP)

          target_page_val = start_page + ((page_number - 1) * step)
          url = Html2rss::Url.from_absolute(page_response.url)

          if url.to_s.include?('{page}')
            Html2rss::Url.from_absolute(url.to_s.gsub('{page}', target_page_val.to_s))
          else
            url.with_query_values(url.query_values.merge(param.to_s => target_page_val.to_s))
          end
        end
      end
    end
  end
end
