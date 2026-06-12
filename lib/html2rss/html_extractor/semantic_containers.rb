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
        cache = {}.compare_by_identity
        candidates = @parsed_body.css(SELECTORS.join(',')).reject do |node|
          HtmlExtractor.ignored_container_path?(node, cache)
        end

        # Preserve the original post-order traversal intent (specific-first)
        # by sorting candidates by depth (descending) while keeping original document
        # order for nodes at the same depth.
        candidates.each_with_index
                  .sort_by { |node, index| [-node.ancestors.size, index] }
                  .map!(&:first)
      end
    end
  end
end
