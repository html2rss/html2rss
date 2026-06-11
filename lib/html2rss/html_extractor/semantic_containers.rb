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
        candidate_set = {}.compare_by_identity
        SELECTORS.each do |sel|
          @parsed_body.css(sel).each do |c|
            candidate_set[c] = true unless HtmlExtractor.ignored_container_path?(c)
          end
        end

        ordered_candidates = []
        @parsed_body.traverse { |n| ordered_candidates << n if candidate_set.delete(n) }
        ordered_candidates
      end
    end
  end
end
