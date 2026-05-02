# frozen_string_literal: true

module Html2rss
  class HtmlExtractor
    ##
    # Collects semantic content containers from a parsed HTML document.
    class SemanticContainers
      # Candidate selectors used to locate extractable semantic content blocks.
      SELECTORS = [
        'article:not(:has(article))',
        'section:not(:has(section))',
        'li:not(:has(li))',
        'tr:not(:has(tr))',
        'div:not(:has(div))'
      ].freeze

      # @param parsed_body [Nokogiri::HTML::Document] parsed document
      # @return [Array<Nokogiri::XML::Node>] candidate semantic containers
      def self.call(parsed_body)
        new(parsed_body).call
      end

      # @param parsed_body [Nokogiri::HTML::Document] parsed document
      def initialize(parsed_body)
        @parsed_body = parsed_body
      end

      # @return [Array<Nokogiri::XML::Node>] candidate semantic containers
      def call
        SELECTORS.each_with_object([]) do |selector, containers|
          collect_selector_containers(selector, containers)
        end
      end

      private

      def collect_selector_containers(selector, containers)
        @parsed_body.css(selector).each do |container|
          next if HtmlExtractor.ignored_container_path?(container)
          next if seen[container]

          seen[container] = true
          containers << container
        end
      end

      def seen
        @seen ||= {}.compare_by_identity
      end
    end
  end
end
