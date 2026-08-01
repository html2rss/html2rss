# frozen_string_literal: true

require_relative 'base'

module Html2rss
  class RequestSession
    module Pager
      ##
      # Paginate using numeric offset increments in query parameters or URL path templates.
      class Offset < Base
        DEFAULT_PARAM = 'offset'
        DEFAULT_START_OFFSET = 0
        DEFAULT_INCREMENT = 20

        private

        # @param page_response [RequestService::Response]
        # @param page_number [Integer]
        # @return [String]
        def next_page_url(page_response, page_number:)
          param = config.fetch(:param, DEFAULT_PARAM)
          start_offset = config.fetch(:start_offset, DEFAULT_START_OFFSET)
          increment = config.fetch(:increment, DEFAULT_INCREMENT)

          target_offset_val = start_offset + ((page_number - 1) * increment)
          base_url_str = page_response.url.to_s

          if base_url_str.include?('{offset}')
            base_url_str.gsub('{offset}', target_offset_val.to_s)
          else
            build_url_with_param(base_url_str, param, target_offset_val)
          end
        end
      end
    end
  end
end
