# frozen_string_literal: true

require_relative 'base'

module Html2rss
  class RequestSession
    module Pager
      ##
      # Traverses a rel=next pagination chain for HTML documents.
      class RelNext < Base
        private

        # @param page_response [RequestService::Response]
        # @param page_number [Integer]
        # @return [String, nil]
        def next_page_url(page_response, page_number: nil) # rubocop:disable Lint/UnusedMethodArgument
          href = page_response.parsed_body.at_css('link[rel~="next"][href], a[rel~="next"][href]')&.[]('href')
          return nil if href.nil? || href.empty?

          Html2rss::Url.from_relative(href, page_response.url)
        end
      end
    end
  end
end
