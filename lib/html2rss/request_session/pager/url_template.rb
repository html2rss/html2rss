# frozen_string_literal: true

require_relative 'base'

module Html2rss
  class RequestSession
    module Pager
      ##
      # Paginate using page number increments in query parameters or URL path templates.
      class UrlTemplate < Base
        DEFAULT_PARAM = 'page'
        DEFAULT_START_PAGE = 1
        DEFAULT_STEP = 1

        private

        # @param page_response [RequestService::Response]
        # @param page_number [Integer] 1-based target page number (e.g. 2 for 2nd page)
        # @return [String]
        def next_page_url(page_response, page_number:)
          param = config.fetch(:param, DEFAULT_PARAM)
          start_page = config.fetch(:start_page, DEFAULT_START_PAGE)
          step = config.fetch(:step, DEFAULT_STEP)

          target_page_val = start_page + ((page_number - 1) * step)
          base_url_str = page_response.url.to_s

          if base_url_str.include?('{page}')
            base_url_str.gsub('{page}', target_page_val.to_s)
          else
            build_url_with_param(base_url_str, param, target_page_val)
          end
        end
      end
    end
  end
end
