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

        candidates = filter_nested_containers(candidates)
        sort_by_depth(candidates)
      end

      private

      def filter_nested_containers(candidates)
        candidate_set = Set.new(candidates)
        rejected = Set.new

        candidates.each do |candidate_b|
          next if candidate_b.name == 'div'

          find_and_reject_ancestors(candidate_b, candidate_set, rejected)
        end

        candidates.reject { |c| rejected.include?(c) }
      end

      def find_and_reject_ancestors(node, candidate_set, rejected)
        curr = node.parent
        while curr && !curr.document? && curr.name != 'html'
          rejected << curr if candidate_set.include?(curr)
          curr = curr.parent
        end
      end

      def sort_by_depth(candidates)
        candidates.each_with_index
                  .sort_by { |node, index| [-node.ancestors.size, index] }
                  .map!(&:first)
      end
    end
  end
end
