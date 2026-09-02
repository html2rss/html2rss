# frozen_string_literal: true

module Html2rss
  module Html
    ##
    # CSS selector compatibility helpers across HTML backends.
    module Css
      # Lexbor CSS gaps vs Nokogiri/libxml; applied only for the nokolexbor backend.
      NOKOGIRI_PSEUDO_MAP = [
        [/:not\(\s*:first-child\s*\)/, ':nth-child(n+2)'],
        [/:not\(\s*:last-child\s*\)/, ':nth-last-child(n+2)'],
        [/:first\b/, ':first-of-type'],
        [/:last\b/, ':last-of-type']
      ].freeze

      module_function

      ##
      # @param selector [String, nil]
      # @param backend [Module]
      # @return [String, nil]
      def normalize(selector, backend: Backend.current)
        return selector if selector.nil? || backend.name != :nokolexbor

        NOKOGIRI_PSEUDO_MAP.reduce(selector.to_s) do |current, (pattern, replacement)|
          current.gsub(pattern, replacement)
        end
      end
    end
  end
end
