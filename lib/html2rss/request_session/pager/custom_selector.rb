# frozen_string_literal: true

module Html2rss
  class RequestSession
    module Pager
      ##
      # Extracts the next-page URL using a configurable CSS or XPath selector.
      class CustomSelector < Base
        private

        # @param page_response [RequestService::Response]
        # @param page_number [Integer]
        # @return [String, nil]
        def next_page_url(page_response, page_number: nil) # rubocop:disable Lint/UnusedMethodArgument
          selector = config[:selector]
          return nil if selector.nil? || selector.empty?

          node = extract_node(page_response.parsed_body, selector)
          return nil unless node

          href = node['href'] || node.text
          return nil if href.nil? || href.strip.empty?

          Html2rss::Url.from_relative(href.strip, page_response.url)
        end

        # @param parsed_body [Nokogiri::HTML::Document]
        # @param selector [String]
        # @return [Nokogiri::XML::Node, nil]
        def extract_node(parsed_body, selector)
          parsed_body.at_css(selector) || parsed_body.at_xpath(selector)
        rescue Nokogiri::CSS::SyntaxError, Nokogiri::XML::XPath::SyntaxError
          # Pure XPath like `descendant::a` fails LOOKS_LIKE_XPATH / at_css; fall back explicitly.
          parsed_body.at_xpath(selector)
        end
      end
    end
  end
end
