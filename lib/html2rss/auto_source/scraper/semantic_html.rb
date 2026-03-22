# frozen_string_literal: true

require_relative 'semantic_html/anchor_selector'

module Html2rss
  class AutoSource
    module Scraper
      ##
      # Scrapes semantic containers by selecting a single content-like anchor
      # within each block before extraction.
      class SemanticHtml
        include Enumerable

        CONTAINER_SELECTORS = [
          'article:not(:has(article))',
          'section:not(:has(section))',
          'li:not(:has(li))',
          'tr:not(:has(tr))',
          'div:not(:has(div))'
        ].freeze

        def self.options_key = :semantic_html

        # @param parsed_body [Nokogiri::HTML::Document] parsed HTML document
        # @return [Boolean] true when at least one semantic container has an eligible anchor
        def self.articles?(parsed_body)
          return false unless parsed_body

          new(parsed_body, url: 'https://example.com').extractable?
        end

        # @param parsed_body [Nokogiri::HTML::Document] parsed HTML document
        # @param url [String, Html2rss::Url] base url
        # @param extractor [Class] extractor class used for article extraction
        def initialize(parsed_body, url:, extractor: HtmlExtractor, **_opts)
          @parsed_body = parsed_body
          @url = url
          @extractor = extractor
          @anchor_selector = AnchorSelector.new(url)
        end

        attr_reader :parsed_body

        ##
        # @yieldparam article_hash [Hash] extracted article hash
        # @return [Enumerator]
        def each
          return enum_for(:each) unless block_given?

          candidate_containers.each do |container|
            selected_anchor = primary_anchor_for(container)
            next unless selected_anchor

            article_hash = @extractor.new(container, base_url: @url, selected_anchor:).call
            yield article_hash if article_hash
          end
        end

        # @return [Boolean] true when at least one candidate container yields a primary anchor
        def extractable?
          candidate_containers.any? { |container| primary_anchor_for(container) }
        end

        protected

        def candidate_containers
          @candidate_containers ||= collect_candidate_containers
        end

        def primary_anchor_for(container)
          @anchor_selector.primary_anchor_for(container)
        end

        def collect_candidate_containers
          seen = {}.compare_by_identity

          CONTAINER_SELECTORS.each_with_object([]) do |selector, containers|
            parsed_body.css(selector).each do |container|
              next if container.path.match?(Html::TAGS_TO_IGNORE)
              next if seen[container]

              seen[container] = true
              containers << container
            end
          end
        end
      end
    end
  end
end
